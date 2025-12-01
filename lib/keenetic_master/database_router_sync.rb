require_relative '../database'
require_relative '../models'
require_relative 'get_all_routes'
require_relative 'apply_route_changes'
require_relative 'delete_routes'
require_relative 'correct_interface'
require 'resolv'
require 'json'
require 'typhoeus'
require 'set'

class KeeneticMaster
  class DatabaseRouterSync < BaseClass
    def initialize
      super
      @logger = logger
    end

    # Generate routes from domain groups and store them in database
    def generate_routes_from_domains!
      @logger.info("Generating routes from domain groups")
      generated_count = 0

      Database.connection.transaction do
        DomainGroup.all.each do |group|
          generated_count += generate_routes_for_group(group)
        end
      end

      @logger.info("Generated #{generated_count} routes from domain groups")
      generated_count
    end

    # Sync pending routes from database to router
    def sync_to_router!
      @logger.info("Starting sync from database to router")

      pending_routes = Route.pending_sync.all
      return Success(message: "No pending routes to sync") if pending_routes.empty?

      routes_data = pending_routes.map(&:to_keenetic_format)
      
      result = ApplyRouteChanges.call(routes_data)
      
      if result.success?
        # Mark routes as synced
        pending_routes.each(&:mark_synced!)
        
        # Log successful sync
        pending_routes.each do |route|
          SyncLog.log_success("add", "route", route.id)
        end
        
        @logger.info("Successfully synced #{pending_routes.size} routes to router")
        Success(synced: pending_routes.size)
      else
        # Log failed sync
        error_message = result.failure.to_s
        pending_routes.each do |route|
          SyncLog.log_error("add", "route", error_message, route.id)
        end
        
        @logger.error("Failed to sync routes to router: #{error_message}")
        Failure(error_message)
      end
    end

    # Sync routes for a specific group: make router routes exactly match database routes
    def sync_group_to_router!(group)
      @logger.info("Starting sync for group '#{group.name}' - making router routes match database")

      # Get all routes for this group from database
      db_routes = Route.where(group_id: group.id).all

      # Get all routes from router
      router_routes_result = GetAllRoutes.new.call
      return router_routes_result if router_routes_result.failure?

      all_router_routes = router_routes_result.value!
      
      # Helper to normalize interface name for comparison
      normalize_interface = lambda do |interface|
        return nil unless interface
        # Correct interface name to match router format
        CorrectInterface.call(interface.to_s)
      end
      
      # Get database network addresses for this group (with normalized interfaces)
      db_networks = db_routes.map do |r|
        normalized_interface = normalize_interface.call(r.interface)
        [r.network, r.mask, normalized_interface]
      end.to_set

      # Filter routes that belong to this group by comment pattern [auto:group_name]
      # OR by matching network+mask+interface if comment is missing
      group_router_routes = all_router_routes.select do |route|
        comment = route[:comment] || ''
        network = route[:network] || route[:dest]
        mask = route[:mask] || route[:genmask] || '255.255.255.255'
        interface = route[:interface] || route[:iface]

        # Match by comment pattern first
        comment_match = comment.match(/\[auto:#{Regexp.escape(group.name)}\]/)

        # Fallback: match by network+mask+interface if comment is missing or doesn't match
        network_match = network && db_networks.include?([network, mask, interface])

        comment_match || network_match
      end

      deleted_count = 0
      added_count = 0

      # Create a set of ALL router routes for comparison (to avoid adding duplicates)
      all_router_routes_set = all_router_routes.map do |r|
        network = r[:network] || r[:dest]
        mask = r[:mask] || r[:genmask] || '255.255.255.255'
        interface = r[:interface] || r[:iface]
        normalized_interface = normalize_interface.call(interface)
        [network, mask, normalized_interface]
      end.to_set

      # Step 1: Delete routes on router that belong to this group but aren't in database
      routes_to_delete = group_router_routes.select do |router_route|
        network = router_route[:network] || router_route[:dest]
        mask = router_route[:mask] || router_route[:genmask] || '255.255.255.255'
        interface = router_route[:interface] || router_route[:iface]
        normalized_interface = normalize_interface.call(interface)
        !db_networks.include?([network, mask, normalized_interface])
      end

      if routes_to_delete.any?
        @logger.info("Preparing to delete #{routes_to_delete.size} routes from router for group '#{group.name}'")
        
        delete_data = routes_to_delete.map do |r|
          route_data = {
            network: r[:network] || r[:dest],
            mask: r[:mask] || r[:genmask] || '255.255.255.255',
            comment: r[:comment]
          }
          # Include interface if present (router might use :interface or :iface)
          interface = r[:interface] || r[:iface]
          route_data[:interface] = interface if interface
          route_data
        end

        @logger.debug("Delete data for #{delete_data.size} routes: #{delete_data.inspect}")

        delete_result = DeleteRoutes.call(delete_data)
        if delete_result.success?
          deleted_count = routes_to_delete.size
          @logger.info("Successfully deleted #{deleted_count} extra routes from router for group '#{group.name}'")
        else
          error_message = delete_result.failure.to_s
          @logger.error("Failed to delete routes from router: #{error_message}")
          # Continue anyway to try adding routes
        end
      end

      # Step 2: Add routes from database that aren't on router
      routes_to_add = db_routes.select do |db_route|
        network = db_route.network
        mask = db_route.mask
        interface = db_route.interface
        normalized_interface = normalize_interface.call(interface)
        !all_router_routes_set.include?([network, mask, normalized_interface])
      end

      if routes_to_add.any?
        add_data = routes_to_add.map do |route|
          route_data = route.to_keenetic_format
          # Correct interface name if needed
          if route_data[:interface]
            route_data[:interface] = CorrectInterface.call(route_data[:interface])
          end
          route_data
        end

        add_result = ApplyRouteChanges.call(add_data)
        if add_result.success?
          added_count = routes_to_add.size
          # Mark routes as synced
          routes_to_add.each(&:mark_synced!)
          
          # Log successful sync
          routes_to_add.each do |route|
            SyncLog.log_success("add", "route", route.id)
          end
          
          @logger.info("Added #{added_count} routes to router for group '#{group.name}'")
        else
          error_message = add_result.failure.to_s
          # Log errors for each route
          routes_to_add.each do |route|
            SyncLog.log_error("add", "route", error_message, route.id)
          end
          
          @logger.error("Failed to add routes to router: #{error_message}")
          return Failure(error_message)
        end
      end

      # Mark all existing routes as synced (they're already on router)
      db_routes.each do |route|
        network = route.network
        mask = route.mask
        interface = route.interface
        normalized_interface = normalize_interface.call(interface)
        if all_router_routes_set.include?([network, mask, normalized_interface]) && !route.synced_to_router
          route.mark_synced!
        end
      end

      @logger.info("Sync completed for group '#{group.name}': added #{added_count}, deleted #{deleted_count}")
      Success(added: added_count, deleted: deleted_count)
    end

    # Sync from router to database (reconciliation)
    def sync_from_router!
      @logger.info("Starting sync from router to database")

      router_routes_result = GetAllRoutes.new.call
      return router_routes_result if router_routes_result.failure?

      router_routes = router_routes_result.value![:message]
      auto_routes = filter_auto_generated_routes(router_routes)
      
      @logger.info("Found #{auto_routes.size} auto-generated routes on router")

      # Find routes that exist on router but not in database
      reconciled_count = 0
      
      auto_routes.each do |router_route|
        db_route = find_matching_database_route(router_route)
        next if db_route

        # Create route in database from router data
        group = extract_group_from_comment(router_route[:comment])
        next unless group

        Route.create(
          group_id: group.id,
          network: router_route[:network] || router_route[:host],
          mask: router_route[:mask] || Constants::MASKS['32'],
          interface: router_route[:interface],
          comment: router_route[:comment],
          synced_to_router: true,
          synced_at: Time.now
        )
        
        reconciled_count += 1
      end

      @logger.info("Reconciled #{reconciled_count} routes from router")
      Success(reconciled: reconciled_count)
    end

    # Full bidirectional sync
    def full_sync!
      @logger.info("Starting full bidirectional sync")

      results = {
        generated: 0,
        synced_to_router: 0,
        reconciled_from_router: 0
      }

      # Step 1: Generate routes from domains
      results[:generated] = generate_routes_from_domains!

      # Step 2: Sync to router
      sync_to_router_result = sync_to_router!
      if sync_to_router_result.success?
        results[:synced_to_router] = sync_to_router_result.value![:synced] || 0
      end

      # Step 3: Reconcile from router
      sync_from_router_result = sync_from_router!
      if sync_from_router_result.success?
        results[:reconciled_from_router] = sync_from_router_result.value![:reconciled] || 0
      end

      @logger.info("Full sync completed: #{results}")
      Success(results)
    end

    # Remove routes that are no longer needed
    def cleanup_obsolete_routes!
      @logger.info("Cleaning up obsolete routes")

      # Find routes in database that don't have corresponding domains
      obsolete_routes = []
      
      Route.all.each do |route|
        group = route.domain_group
        next unless group
        
        # Check if the route is still needed based on current domains
        if !route_still_needed?(route, group)
          obsolete_routes << route
        end
      end

      return Success(message: "No obsolete routes found") if obsolete_routes.empty?

      @logger.info("Found #{obsolete_routes.size} obsolete routes to cleanup")

      # Delete from router first
      routes_to_delete = obsolete_routes.map { |r| { network: r.network, mask: r.mask } }
      delete_result = DeleteRoutes.call(routes_to_delete)

      if delete_result.success?
        # Remove from database
        obsolete_routes.each do |route|
          SyncLog.log_success("delete", "route", route.id)
          route.destroy
        end
        
        @logger.info("Successfully cleaned up #{obsolete_routes.size} obsolete routes")
        Success(cleaned_up: obsolete_routes.size)
      else
        error_message = delete_result.failure.to_s
        obsolete_routes.each do |route|
          SyncLog.log_error("delete", "route", error_message, route.id)
        end
        
        @logger.error("Failed to cleanup obsolete routes: #{error_message}")
        Failure(error_message)
      end
    end

    private

    def generate_routes_for_group(group)
      interface_string = group.interfaces || ENV['KEENETIC_VPN_INTERFACES'] || 'Wireguard0'
      interfaces = interface_string.split(',').map(&:strip)
      
      # Get DNS monitored domains for this group
      # Regular domains are no longer supported - only DNS monitored domains
      dns_domains = group.domains_dataset.where(type: 'follow_dns').all
      
      # Generate fresh routes from current domains
      fresh_routes = []
      dns_domains.each do |domain|
        routes = resolve_domain_to_routes(domain.domain, group, interfaces)
        fresh_routes.concat(routes)
      end
      
      # Create a set of fresh routes for comparison (network, mask, interface, comment)
      # Include comment to allow multiple domains to have the same IP ranges
      fresh_routes_set = fresh_routes.map { |r| [r[:network], r[:mask], r[:interface], r[:comment]] }.to_set
      
      # Get all existing routes for this group from database
      existing_routes = Route.where(group_id: group.id).all
      
      # Remove duplicate routes per domain (same network/mask/interface/comment)
      # Keep only the first occurrence of each unique route
      seen_existing = Set.new
      routes_to_remove_duplicates = []
      existing_routes.each do |existing|
        route_key = [existing.network, existing.mask, existing.interface, existing.comment]
        if seen_existing.include?(route_key)
          routes_to_remove_duplicates << existing
        else
          seen_existing.add(route_key)
        end
      end
      
      # Remove duplicates first
      routes_to_remove_duplicates.each do |route|
        route.destroy
      end
      
      # Reload existing routes after removing duplicates
      existing_routes = Route.where(group_id: group.id).all if routes_to_remove_duplicates.any?
      
      # Find routes to add (in fresh but not in database)
      # Compare by network, mask, interface, AND comment to allow duplicates with different domains
      routes_to_add = fresh_routes.select do |fresh_route|
        !existing_routes.any? do |existing|
          existing.network == fresh_route[:network] &&
          existing.mask == fresh_route[:mask] &&
          existing.interface == fresh_route[:interface] &&
          existing.comment == fresh_route[:comment]
        end
      end
      
      # Find routes to remove (in database but not in fresh)
      # Include comment in comparison to preserve routes for different domains with same IP ranges
      routes_to_remove = existing_routes.select do |existing|
        !fresh_routes_set.include?([existing.network, existing.mask, existing.interface, existing.comment])
      end
      
      # Add new routes
      added_count = 0
      routes_to_add.each do |route_data|
        Route.create(route_data.merge(group_id: group.id))
        added_count += 1
      end
      
      # Remove obsolete routes
      removed_count = 0
      routes_to_remove.each do |route|
        route.destroy
        removed_count += 1
      end
      
      duplicate_removed_count = routes_to_remove_duplicates.size
      total_removed = removed_count + duplicate_removed_count
      
      @logger.info("Generated routes for group '#{group.name}': added #{added_count}, removed #{removed_count} obsolete, removed #{duplicate_removed_count} duplicates, total fresh routes: #{fresh_routes.size}")
      
      added_count
    end

    def resolve_domain_to_routes(domain_string, group, interfaces)
      routes = []
      domain_mask = group.mask || ENV.fetch('DOMAINS_MASK', '32').to_s
      seen_routes = Set.new
      
      if domain_string =~ /^\d+\.\d+\.\d+\.\d+(?:\/\d+)?$/ || domain_string =~ /^\d+\.\d+\.\d+\.\d+$/
        # IP address or CIDR
        if domain_string.include?('/')
          network, cidr = domain_string.split('/')
          mask = Constants::MASKS[cidr.to_s]
        else
          network = domain_string
          mask = Constants::MASKS['32']
        end
        
        interfaces.each do |interface|
          route_key = [network, mask, interface]
          next if seen_routes.include?(route_key)
          seen_routes.add(route_key)
          
          routes << {
            network: network,
            mask: mask,
            interface: interface,
            comment: "[auto:#{group.name}] #{domain_string}",
            synced_to_router: false
          }
        end
      else
        # Domain name - perform DNS resolution
        begin
          dns_servers = ENV.fetch('DNS_SERVERS', nil)&.split(',') || ['1.1.1.1', '8.8.8.8']
          
          dns_servers.each do |nameserver|
            begin
              resolver = Resolv::DNS.new(nameserver: nameserver)
              ips = resolver.getaddresses(domain_string)
              
              # Deduplicate IPs first
              unique_ips = ips.select { |ip| ip.is_a?(Resolv::IPv4) }.uniq
              
              unique_ips.each do |ip|
                ip_str = ip.to_s
                network = ip_str.sub(/\.\d+$/, '.0')
                mask = Constants::MASKS[domain_mask.to_s]
                
                interfaces.each do |interface|
                  route_key = [network, mask, interface]
                  next if seen_routes.include?(route_key)
                  seen_routes.add(route_key)
                  
                  routes << {
                    network: network,
                    mask: mask,
                    interface: interface,
                    comment: "[auto:#{group.name}] #{domain_string}",
                    synced_to_router: false
                  }
                end
              end
              break # Use the first working DNS server
            rescue => dns_error
              @logger.warn("DNS resolution failed for #{domain_string} using #{nameserver}: #{dns_error.message}")
              next # Try next DNS server
            end
          end
        rescue => e
          @logger.error("Failed to resolve domain #{domain_string}: #{e.message}")
        end
      end

      routes
    end

    def filter_auto_generated_routes(routes)
      routes.select { |route| route[:comment]&.start_with?('[auto:') }
    end

    def find_matching_database_route(router_route)
      Route.find(
        network: router_route[:network] || router_route[:host],
        mask: router_route[:mask] || Constants::MASKS['32'],
        interface: router_route[:interface]
      )
    end

    def extract_group_from_comment(comment)
      return nil unless comment&.start_with?('[auto:')
      
      match = comment.match(/\[auto:([^\]]+)\]/)
      return nil unless match
      
      group_name = match[1]
      DomainGroup.find(name: group_name)
    end

    def route_still_needed?(route, group)
      # Check if any DNS monitored domains exist in the group
      group.domains_dataset.where(type: 'follow_dns').any?
    end
  end
end
