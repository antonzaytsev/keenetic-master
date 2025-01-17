require_relative 'mutate_route_request'

class KeeneticMaster
  class DeleteRoute < MutateRouteRequest
    def call(host: nil, network: nil, mask: nil)
      route = {
        "no" => true,
      }

      process_host(route, host:, network:, mask:)
      body = build_body(route)

      make_request(body)
    end
  end
end
