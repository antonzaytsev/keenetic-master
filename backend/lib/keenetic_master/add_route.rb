require_relative 'mutate_route_request'

class KeeneticMaster
  class AddRoute < MutateRouteRequest
    def call(comment:, host: nil, network: nil, mask: nil, interface: nil)
      if interface.nil?
        logger.info "Используется дефолтный интерфейс для VPN: 'Wireguard0'"
        interface = 'Wireguard0'
      end

      route = {
        gateway: "",
        auto: true,
        reject: false,
        comment: comment,
        interface: interface
      }

      process_host(route, host:, network:, mask:)

      body = build_body(route)
      make_request(body)
    end
  end
end
