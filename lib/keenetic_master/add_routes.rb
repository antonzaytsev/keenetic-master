require_relative 'mutate_route_request'

class KeeneticMaster
  class AddRoutes < MutateRouteRequest
    def call(routes)
      return Success(empty: true) if routes.empty?

      routes.each do |route|
        route[:gateway] ||= ''
        route[:auto] = true unless route.key?(:auto)
        route[:reject] = false unless route.key?(:reject)

        process_host(route, host: route[:host], network: route[:network], mask: route[:mask])
      end

      body = build_body_routes(routes)
      make_request(body)
    end
  end
end
