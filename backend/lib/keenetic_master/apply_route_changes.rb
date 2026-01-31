require_relative 'mutate_route_request'

class KeeneticMaster
  class ApplyRouteChanges < MutateRouteRequest
    # @param routes [Array<Hash>]
    def call(routes)
      return Success(empty: true) if routes.empty?

      response = Client.new.post_rci(build_body_routes(routes))
      return Failure(response:) if response.code != 200

      Success()
    end
  end
end
