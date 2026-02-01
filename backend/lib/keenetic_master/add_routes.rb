class KeeneticMaster
  class AddRoutes < BaseClass
    def call(routes)
      return Success(empty: true) if routes.empty?

      # Transform routes to gem format
      gem_routes = routes.map do |route|
        transform_route(route)
      end

      Configuration.keenetic_client.routes.add_batch(gem_routes)
      Success(message: "#{routes.size} route(s) added successfully")
    rescue Keenetic::ApiError => e
      logger.error("AddRoutes failed: #{e.message}")
      Failure(message: "Failed to add routes: #{e.message}")
    end

    private

    def transform_route(route)
      result = {
        interface: route[:interface] || 'Wireguard0',
        comment: route[:comment]
      }

      if route[:host]
        result[:host] = route[:host]
      elsif route[:network]
        # Support CIDR notation or network/mask pair
        if route[:mask]
          cidr = Constants::MASKS.key(route[:mask]) || '32'
          result[:network] = "#{route[:network]}/#{cidr}"
        else
          result[:network] = route[:network]
        end
      end

      result
    end
  end
end
