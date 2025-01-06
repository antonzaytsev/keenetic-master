require 'typhoeus'

class KeeneticMaster
  class AaMutateRouteRequest < ARouteRequest
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

      result = JSON.parse(response.body).detect { |el| el['ip'] }.dig('ip', 'route', 'status', 0)

      if result['status'] == 'error'
        return Failure(result['status'] => result['message'])
      end

      # todo modify this to return message about all affected rows
      Success(message: result['message'])
    end
  end
end
