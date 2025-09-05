require 'typhoeus'
require 'json'

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
      body = [
        {"show": {"sc": {"ip": {"route": {}}}}}
      ]

      response = Client.post_rci(body)
      return Failure(request_failure: response, error: "Failed to connect to router") if response.code != 200

      begin
        result = JSON.parse(response.body).dig(0, 'show', 'sc', 'ip', 'route')
        return Failure(error: "No route data in response") unless result

        routes = result.map do |row|
          row.transform_keys(&:to_sym)
        end

        Success(routes)
      rescue JSON::ParserError => e
        Failure(error: "Failed to parse router response: #{e.message}")
      end
    end
  end
end
