require_relative '../database'
require_relative '../models'
require_relative 'get_all_routes'
require_relative 'apply_route_changes'
require_relative 'delete_routes'
require_relative 'correct_interface'
require 'resolv'
require 'json'
require 'typhoeus'

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
      generated_count = 0
      interfaces = group.interfaces_list.presence || [ENV['KEENETIC_VPN_INTERFACES'] || 'Wireguard0']
      
      # Get regular domains for this group
      regular_domains = group.domains_dataset.where(type: 'regular').all
      
      regular_domains.each do |domain|
        routes = resolve_domain_to_routes(domain.domain, group, interfaces)
        routes.each do |route_data|
          # Check if route already exists
          existing = Route.find(
            group_id: group.id,
            network: route_data[:network],
            mask: route_data[:mask],
            interface: route_data[:interface]
          )
          
          unless existing
            Route.create(route_data.merge(group_id: group.id))
            generated_count += 1
          end
        end
      end

      generated_count
    end

    def resolve_domain_to_routes(domain_string, group, interfaces)
      routes = []
      
      if domain_string =~ /^\d+\.\d+\.\d+\.\d+(?:\/\d+)?$/ || domain_string =~ /^\d+\.\d+\.\d+\.\d+$/
        # IP address or CIDR
        if domain_string.include?('/')
          network, cidr = domain_string.split('/')
          mask = Constants::MASKS[cidr]
        else
          network = domain_string
          mask = Constants::MASKS['32']
        end
        
        interfaces.each do |interface|
          routes << {
            network: network,
            mask: mask,
            interface: interface,
            comment: "[auto:#{group.name}] #{domain_string}",
            synced_to_router: false
          }
        end
      else
        # Domain name - would need DNS resolution
        # For now, we'll skip DNS resolution and let the existing domain resolution logic handle it
        # This is a placeholder for future implementation
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
      # This is a simplified check - in reality, you'd want to check if the
      # route corresponds to any current domains in the group
      !group.domains.empty?
    end
  end
end
