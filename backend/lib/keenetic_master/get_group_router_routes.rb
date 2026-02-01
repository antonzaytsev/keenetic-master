class KeeneticMaster
  class GetGroupRouterRoutes < BaseClass
    def call(group_name)
      # Get all routes from router
      router_result = get_router_routes
      return router_result if router_result.failure?

      # Get database routes for this group to know which networks to look for
      group = DomainGroup.find(name: group_name)
      return Failure(error: "Group not found") unless group

      group_networks = Route.where(group_id: group.id).select_map(:network)
      
      # Filter router routes to match our group's networks
      router_routes = router_result.value!
      matching_routes = router_routes.select do |route|
        network = route[:network] || route[:dest]
        network && group_networks.include?(network)
      end

      Success({
        routes: matching_routes,
        total_router_routes: router_routes.size,
        matching_routes: matching_routes.size
      })
    end

    private

    def get_router_routes
      routes = Configuration.keenetic_client.routes.all
      routes = routes.map { |row| row.transform_keys(&:to_sym) }
      Success(routes)
    rescue Keenetic::ApiError => e
      logger.error("Failed to get routes: #{e.message}")
      Failure(error: "Failed to connect to router: #{e.message}")
    end
  end
end
