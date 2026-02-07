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
  class RouterRoutesManager < BaseClass
    def initialize
      super
      @logger = logger
    end

    # Push routes for a specific group: generate routes from domains and push to router
    def push_group_routes!(group)
      @logger.info("Pushing routes for group '#{group.name}' to router")

      # Generate fresh routes from current domains
      fresh_routes = generate_routes_for_group(group)
      
      # Pull all routes from router
      router_routes_result = GetAllRoutes.new.call
      return router_routes_result if router_routes_result.failure?

      all_router_routes = router_routes_result.value!
      
      # Helper to normalize interface name for comparison
      normalize_interface = lambda do |interface|
        return nil unless interface
        CorrectInterface.call(interface.to_s)
      end
      
      # Get fresh routes network addresses (with normalized interfaces)
      fresh_routes_set = fresh_routes.map do |r|
        normalized_interface = normalize_interface.call(r[:interface])
        [r[:network], r[:mask], normalized_interface]
      end.to_set

      # Filter routes that belong to this group by comment pattern [auto:group_name]
      group_router_routes = all_router_routes.select do |route|
        comment = route[:comment] || ''
        comment.match(/\[auto:#{Regexp.escape(group.name)}\]/)
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

      # Step 1: Delete routes on router that belong to this group but aren't in fresh routes
      routes_to_delete = group_router_routes.select do |router_route|
        network = router_route[:network] || router_route[:dest]
        mask = router_route[:mask] || router_route[:genmask] || '255.255.255.255'
        interface = router_route[:interface] || router_route[:iface]
        normalized_interface = normalize_interface.call(interface)
        !fresh_routes_set.include?([network, mask, normalized_interface])
      end

      if routes_to_delete.any?
        @logger.info("Preparing to delete #{routes_to_delete.size} routes from router for group '#{group.name}'")
        
        delete_data = routes_to_delete.map do |r|
          route_data = {
            network: r[:network] || r[:dest],
            mask: r[:mask] || r[:genmask] || '255.255.255.255',
            comment: r[:comment]
          }
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
        end
      end

      # Step 2: Add routes that aren't on router yet
      routes_to_add = fresh_routes.select do |fresh_route|
        network = fresh_route[:network]
        mask = fresh_route[:mask]
        interface = fresh_route[:interface]
        normalized_interface = normalize_interface.call(interface)
        !all_router_routes_set.include?([network, mask, normalized_interface])
      end

      if routes_to_add.any?
        add_data = routes_to_add.map do |route|
          route_data = route.dup
          if route_data[:interface]
            route_data[:interface] = CorrectInterface.call(route_data[:interface])
          end
          route_data
        end

        add_result = ApplyRouteChanges.call(add_data)
        if add_result.success?
          added_count = routes_to_add.size
          @logger.info("Added #{added_count} routes to router for group '#{group.name}'")
        else
          error_message = add_result.failure.to_s
          @logger.error("Failed to add routes to router: #{error_message}")
          return Failure(error_message)
        end
      end

      @logger.info("Push completed for group '#{group.name}': added #{added_count}, deleted #{deleted_count}")
      Success(added: added_count, deleted: deleted_count)
    end

    # Push routes for all groups
    def push_all_routes!
      @logger.info("Pushing routes for all groups to router")

      results = {
        groups_processed: 0,
        total_added: 0,
        total_deleted: 0,
        errors: []
      }

      DomainGroup.all.each do |group|
        begin
          result = push_group_routes!(group)
          
          if result.success?
            data = result.value!
            results[:groups_processed] += 1
            results[:total_added] += data[:added]
            results[:total_deleted] += data[:deleted]
          else
            results[:errors] << "#{group.name}: #{result.failure}"
          end
        rescue => e
          @logger.error("Failed to push routes for group '#{group.name}': #{e.message}")
          results[:errors] << "#{group.name}: #{e.message}"
        end
      end

      @logger.info("Push all completed: #{results}")
      Success(results)
    end

    # Remove routes that are no longer needed (cleanup orphaned routes)
    def cleanup_obsolete_routes!
      @logger.info("Cleaning up obsolete routes")

      router_routes_result = GetAllRoutes.new.call
      return router_routes_result if router_routes_result.failure?

      router_routes = router_routes_result.value!
      
      # Find auto-generated routes
      auto_routes = router_routes.select { |route| route[:comment]&.start_with?('[auto:') }
      
      # Group routes by their group name from comment
      routes_by_group = {}
      auto_routes.each do |route|
        match = route[:comment]&.match(/\[auto:([^\]]+)\]/)
        next unless match
        group_name = match[1]
        routes_by_group[group_name] ||= []
        routes_by_group[group_name] << route
      end

      obsolete_routes = []
      
      routes_by_group.each do |group_name, routes|
        group = DomainGroup.find(name: group_name)
        
        if group.nil?
          # Group no longer exists, all its routes are obsolete
          obsolete_routes.concat(routes)
        else
          # Check if routes are still needed based on current domains
          fresh_routes = generate_routes_for_group(group)
          fresh_routes_set = fresh_routes.map { |r| [r[:network], r[:mask], CorrectInterface.call(r[:interface])] }.to_set
          
          routes.each do |route|
            network = route[:network] || route[:dest]
            mask = route[:mask] || route[:genmask] || '255.255.255.255'
            interface = CorrectInterface.call(route[:interface] || route[:iface])
            
            unless fresh_routes_set.include?([network, mask, interface])
              obsolete_routes << route
            end
          end
        end
      end

      return Success(message: "No obsolete routes found", cleaned_up: 0) if obsolete_routes.empty?

      @logger.info("Found #{obsolete_routes.size} obsolete routes to cleanup")

      routes_to_delete = obsolete_routes.map do |r|
        {
          network: r[:network] || r[:dest],
          mask: r[:mask] || r[:genmask] || '255.255.255.255',
          comment: r[:comment]
        }
      end
      
      delete_result = DeleteRoutes.call(routes_to_delete)

      if delete_result.success?
        @logger.info("Successfully cleaned up #{obsolete_routes.size} obsolete routes")
        Success(cleaned_up: obsolete_routes.size)
      else
        error_message = delete_result.failure.to_s
        @logger.error("Failed to cleanup obsolete routes: #{error_message}")
        Failure(error_message)
      end
    end

    # Pull routes for a specific group from router
    def pull_group_routes(group)
      router_routes_result = GetAllRoutes.new.call
      return router_routes_result if router_routes_result.failure?

      router_routes = router_routes_result.value!
      
      # Filter routes that belong to this group by comment pattern
      group_routes = router_routes.select do |route|
        comment = route[:comment] || ''
        comment.match(/\[auto:#{Regexp.escape(group.name)}\]/)
      end

      Success(routes: group_routes, total: group_routes.size)
    end

    private

    def generate_routes_for_group(group)
      interface_string = group.interfaces || Configuration.vpn_interface
      interfaces = interface_string.split(',').map(&:strip)
      
      dns_domains = group.domains_dataset.where(type: 'follow_dns').all
      
      routes = []
      seen_routes = Set.new
      
      dns_domains.each do |domain|
        domain_routes = resolve_domain_to_routes(domain.domain, group, interfaces)
        domain_routes.each do |route|
          route_key = [route[:network], route[:mask], route[:interface]]
          unless seen_routes.include?(route_key)
            seen_routes.add(route_key)
            routes << route
          end
        end
      end
      
      @logger.info("Generated #{routes.size} routes for group '#{group.name}'")
      routes
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
            comment: "[auto:#{group.name}] #{domain_string}"
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
                    comment: "[auto:#{group.name}] #{domain_string}"
                  }
                end
              end
              break # Use the first working DNS server
            rescue => dns_error
              @logger.warn("DNS resolution failed for #{domain_string} using #{nameserver}: #{dns_error.message}")
              next
            end
          end
        rescue => e
          @logger.error("Failed to resolve domain #{domain_string}: #{e.message}")
        end
      end

      routes
    end
  end
end
