require_relative 'mutate_route_request'

class KeeneticMaster
  class DeleteRoutes < MutateRouteRequest
    def call(routes)
      return Success(empty: true) if routes.empty?

      modified_routes = routes.map do |route|
        process_route(route).merge(comment: route[:comment], no: true)
      end

      response = Client.new.post_rci(build_body_routes(modified_routes))
      return Failure(response) if response.code != 200

      Success()
    end
  end
end
