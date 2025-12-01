require_relative '../database'
require_relative '../models'
require_relative 'database_router_sync'
require_relative 'apply_route_changes'
require_relative 'delete_routes'
require_relative 'correct_interface'
require 'resolv'

class KeeneticMaster
  class UpdateRoutesDatabase < BaseClass
    def initialize
      super
      @sync_service = DatabaseRouterSync.new
      @logger = logger
    end

    # Update routes for a specific group
    def call(group_name)
      @logger.info("Starting database route update for group: #{group_name}")
      start_time = Time.now

      group = DomainGroup.find(name: group_name)
      unless group
        return Failure(message: "Domain group '#{group_name}' not found")
      end

      begin
        # Generate routes for this specific group
        generated_count = generate_routes_for_group(group)
        
        # Sync only routes for this group to router
        synced_count = sync_group_routes_to_router(group)
        
        # Cleanup obsolete routes for this group
        cleaned_count = cleanup_group_routes(group)
        
        elapsed_time = (Time.now - start_time).round(2)
        message = "Successfully processed group '#{group_name}'. Generated: #{generated_count}, synced: #{synced_count}, cleaned: #{cleaned_count}. Time: #{elapsed_time}s"
        
        @logger.info(message)
        
        Success(
          group: group_name,
          generated: generated_count,
          synced: synced_count,
          cleaned: cleaned_count,
          message: message
        )
        
      rescue => e
        @logger.error("Failed to update routes for group '#{group_name}': #{e.message}")
        Failure(message: e.message)
      end
    end

    # Update routes for all groups
    def call_all
      @logger.info("Starting database route update for all groups")
      start_time = Time.now

      results = {
        groups_processed: 0,
        total_generated: 0,
        total_synced: 0,
        total_cleaned: 0,
        errors: []
      }

      DomainGroup.all.each do |group|
        begin
          result = call(group.name)
          
          if result.success?
            data = result.value!
            results[:groups_processed] += 1
            results[:total_generated] += data[:generated]
            results[:total_synced] += data[:synced]
            results[:total_cleaned] += data[:cleaned]
          else
            results[:errors] << "#{group.name}: #{result.failure[:message]}"
          end
          
        rescue => e
          @logger.error("Failed to process group '#{group.name}': #{e.message}")
          results[:errors] << "#{group.name}: #{e.message}"
        end
      end

      elapsed_time = (Time.now - start_time).round(2)
      
      if results[:errors].empty?
        message = "Successfully processed all #{results[:groups_processed]} groups. Generated: #{results[:total_generated]}, synced: #{results[:total_synced]}, cleaned: #{results[:total_cleaned]}. Time: #{elapsed_time}s"
        @logger.info(message)
        
        Success(results.merge(message: message))
      else
        message = "Processed #{results[:groups_processed]} groups with #{results[:errors].size} errors. Time: #{elapsed_time}s"
        @logger.warn(message)
        @logger.warn("Errors: #{results[:errors].join(', ')}")
        
        Failure(results.merge(message: message))
      end
    end

    # Minimize mode - use database sync for efficiency
    def call_minimize(delete_missing: true)
      @logger.info("Starting minimize mode update using database sync")
      
      result = @sync_service.full_sync!
      
      if delete_missing && result.success?
        cleanup_result = @sync_service.cleanup_obsolete_routes!
        if cleanup_result.success?
          cleaned_count = cleanup_result.value![:cleaned_up] || 0
          result.value![:cleaned_up] = cleaned_count
        end
      end
      
      result
    end

    private

    def generate_routes_for_group(group)
      generated_count = 0
      interfaces = group.interfaces_list.presence || Configuration.vpn_interfaces
      mask = group.mask || Configuration.domains_mask
      
      # Get DNS monitored domains for this group
      # Regular domains are no longer supported - only DNS monitored domains
      dns_domains = group.domains_dataset.where(type: 'follow_dns').all
      
      dns_domains.each do |domain|
        routes = resolve_domain_to_routes(domain.domain, group, interfaces, mask)
        routes.each do |route_data|
          # Check if route already exists
          existing = Route.find(
            group_id: group.id,
            network: route_data[:network],
            mask: route_data[:mask],
            interface: route_data[:interface]
          )
          
          unless existing
            Route.create(route_data.merge(group_id: group.id, synced_to_router: false))
            generated_count += 1
          end
        end
      end

      generated_count
    end

    def sync_group_routes_to_router(group)
      # Get pending routes for this group only
      pending_routes = Route.where(group_id: group.id, synced_to_router: false).all
      return 0 if pending_routes.empty?

      routes_data = pending_routes.map(&:to_keenetic_format)
      
      result = ApplyRouteChanges.call(routes_data)
      
      if result.success?
        # Mark routes as synced
        pending_routes.each(&:mark_synced!)
        
        # Log successful sync
        pending_routes.each do |route|
          SyncLog.log_success("add", "route", route.id)
        end
        
        @logger.info("Successfully synced #{pending_routes.size} routes for group '#{group.name}'")
        pending_routes.size
      else
        # Log failed sync
        error_message = result.failure.to_s
        pending_routes.each do |route|
          SyncLog.log_error("add", "route", error_message, route.id)
        end
        
        @logger.error("Failed to sync routes for group '#{group.name}': #{error_message}")
        raise StandardError, "Sync failed: #{error_message}"
      end
    end

    def cleanup_group_routes(group)
      # Find routes for this group that are no longer needed
      current_routes = Route.where(group_id: group.id, synced_to_router: true).all
      obsolete_routes = []
      
      current_routes.each do |route|
        unless route_still_needed?(route, group)
          obsolete_routes << route
        end
      end

      return 0 if obsolete_routes.empty?

      # Delete from router first
      routes_to_delete = obsolete_routes.map { |r| { network: r.network, mask: r.mask } }
      delete_result = DeleteRoutes.call(routes_to_delete)

      if delete_result.success?
        # Remove from database
        obsolete_routes.each do |route|
          SyncLog.log_success("delete", "route", route.id)
          route.destroy
        end
        
        @logger.info("Cleaned up #{obsolete_routes.size} obsolete routes for group '#{group.name}'")
        obsolete_routes.size
      else
        error_message = delete_result.failure.to_s
        obsolete_routes.each do |route|
          SyncLog.log_error("delete", "route", error_message, route.id)
        end
        
        @logger.error("Failed to cleanup routes for group '#{group.name}': #{error_message}")
        raise StandardError, "Cleanup failed: #{error_message}"
      end
    end

    def resolve_domain_to_routes(domain_string, group, interfaces, mask)
      routes = []
      
      if domain_string =~ /^\d+\.\d+\.\d+\.\d+(?:\/\d+)?$/ || domain_string =~ /^\d+\.\d+\.\d+\.\d+$/
        # IP address or CIDR
        if domain_string.include?('/')
          network, cidr = domain_string.split('/')
          route_mask = Constants::MASKS[cidr]
        else
          network = calculate_network_for_ip(domain_string, mask)
          route_mask = Constants::MASKS[mask]
        end
        
        interfaces.each do |interface|
          routes << {
            network: network,
            mask: route_mask,
            interface: CorrectInterface.call(interface),
            comment: "[auto:#{group.name}] #{domain_string}"
          }
        end
      else
        # Domain name - DNS resolution
        routes.concat(resolve_dns_routes(domain_string, group, interfaces, mask))
      end

      routes
    end

    def calculate_network_for_ip(ip_address, mask)
      if mask == '24'
        ip_address.sub(/\.\d+$/, '.0')
      else
        ip_address
      end
    end

    def resolve_dns_routes(domain, group, interfaces, mask)
      routes = []
      route_mask = Constants::MASKS[mask]
      
      begin
        dns_resolvers = Configuration.dns_servers.map { |ns| Resolv::DNS.new(nameserver: ns) }
        
        dns_resolvers.each do |resolver|
          addresses = resolver.getresources(domain, Resolv::DNS::Resource::IN::A)
          
          addresses.each do |address|
            ip_address = address.address.to_s
            next if ip_address.start_with?('127.')
            
            network = calculate_network_for_ip(ip_address, mask)
            
            interfaces.each do |interface|
              routes << {
                network: network,
                mask: route_mask,
                interface: CorrectInterface.call(interface),
                comment: "[auto:#{group.name}] #{domain}"
              }
            end
          end
        end
        
      rescue Resolv::ResolvError => e
        @logger.warn("Failed to resolve #{domain}: #{e.message}")
      rescue => e
        @logger.error("DNS resolution error for #{domain}: #{e.message}")
      end
      
      routes.uniq { |r| [r[:network], r[:mask], r[:interface]] }
    end

    def route_still_needed?(route, group)
      # Check if any DNS monitored domain in the group would still generate this route
      # Regular domains are no longer supported
      group.domains_dataset.where(type: 'follow_dns').any? do |domain|
        potential_routes = resolve_domain_to_routes(domain.domain, group, [route.interface], group.mask || Configuration.domains_mask)
        potential_routes.any? do |potential|
          potential[:network] == route.network && potential[:mask] == route.mask
        end
      end
    end
  end
end
