class KeeneticMaster
  class AddRoute < BaseClass
    def call(comment:, host: nil, network: nil, mask: nil, interface: nil)
      interface ||= 'Wireguard0'
      logger.info "Using interface: '#{interface}'" if interface == 'Wireguard0'

      route_params = {
        interface: interface,
        comment: comment
      }

      # Handle host vs network/mask
      if host
        route_params[:host] = host
      elsif network
        # Support CIDR notation (e.g., "10.0.0.0/24")
        route_params[:network] = mask ? "#{network}/#{cidr_from_mask(mask)}" : network
      end

      Configuration.keenetic_client.routes.add(**route_params)
      Success(message: "Route added successfully")
    rescue Keenetic::ApiError => e
      logger.error("AddRoute failed: #{e.message}")
      Failure(message: "Failed to add route: #{e.message}")
    end

    private

    def cidr_from_mask(mask)
      Constants::MASKS.key(mask) || '32'
    end
  end
end
