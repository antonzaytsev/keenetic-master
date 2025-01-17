class KeeneticMaster
  class MutateRouteRequest < BaseClass
    private

    def process_host(route, host:, network:, mask:)
      if host && host =~ /\//
        network, cidr_notation = host.split('/')
        mask = MASKS.fetch(cidr_notation)
        host = nil
      end

      if host
        route[:host] = host
      else
        route[:network] = network
        route[:mask] = mask
      end
    end

    def process_route(route)
      if route[:host] && route[:host] =~ /\//
        route[:network], cidr_notation = route[:host].split('/')
        route[:mask] = MASKS.fetch(cidr_notation)
        route.delete(:host)
      end

      if route[:host]
        route.slice(:host)
      else
        route.slice(:network, :mask)
      end
    end

    def build_body(route)
      [
        {"webhelp": {"event": {"push": {"data": {type: :configuration_change, value: { url: "/staticRoutes" }}.to_json}}}},
        {"ip": {"route": route}},
        {"system": {"configuration": {"save": {}}}}
      ]
    end

    def build_body_routes(routes)
      [
        {"webhelp": {"event": {"push": {"data": {type: :configuration_change, value: { url: "/staticRoutes" }}.to_json}}}},
        *routes.map { |route| {"ip": {"route": route}} },
        {"system": {"configuration": {"save": {}}}}
      ]
    end

    def make_request(body)
      response = Client.new.post_rci(body)
      return Failure(request_failure: response) if response.code != 200

      # TODO: modify this part to check if all provided rows are successfully processed
      result = JSON.parse(response.body).detect { |el| el['ip'] }.dig('ip', 'route', 'status', 0)
      if result['status'] == 'error'
        return Failure(result['status'] => result['message'])
      end
      Success(message: result['message'])
    end
  end
end
