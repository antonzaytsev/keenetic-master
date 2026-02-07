class KeeneticMaster
  class GetGroupRouterRoutes < BaseClass
    def call(group_name)
      # Get all routes from router
      router_result = get_router_routes
      return router_result if router_result.failure?

      # Verify group exists
      group = DomainGroup.find(name: group_name)
      return Failure(error: "Group not found") unless group

      router_routes = router_result.value!
      
      # Filter routes that belong to this group by comment pattern [auto:group_name]
      matching_routes = router_routes.select do |route|
        comment = route[:comment] || ''
        comment.match(/\[auto:#{Regexp.escape(group_name)}\]/)
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
