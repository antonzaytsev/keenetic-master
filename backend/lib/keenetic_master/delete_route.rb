class KeeneticMaster
  class DeleteRoute < BaseClass
    def call(host: nil, network: nil, mask: nil)
      route_params = {}

      if host
        route_params[:host] = host
      elsif network
        # Support CIDR notation or network/mask pair
        if mask
          cidr = Constants::MASKS.key(mask) || '32'
          route_params[:network] = "#{network}/#{cidr}"
        else
          route_params[:network] = network
        end
      end

      Configuration.keenetic_client.routes.delete(**route_params)
      Success(message: "Route deleted successfully")
    rescue Keenetic::ApiError => e
      logger.error("DeleteRoute failed: #{e.message}")
      Failure(message: "Failed to delete route: #{e.message}")
    end
  end
end
