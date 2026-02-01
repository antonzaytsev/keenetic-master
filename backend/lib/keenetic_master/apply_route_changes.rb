class KeeneticMaster
  class ApplyRouteChanges < BaseClass
    # @param routes [Array<Hash>]
    # Routes can have :no => true for deletion
    def call(routes)
      return Success(empty: true) if routes.empty?

      routes_to_add = routes.reject { |r| r[:no] }
      routes_to_delete = routes.select { |r| r[:no] }

      client = Configuration.keenetic_client

      # Add routes
      if routes_to_add.any?
        gem_routes = routes_to_add.map { |r| transform_route_for_add(r) }
        client.routes.add_batch(gem_routes)
      end

      # Delete routes
      routes_to_delete.each do |route|
        route_params = transform_route_for_delete(route)
        client.routes.delete(**route_params)
      rescue Keenetic::ApiError => e
        logger.warn("Failed to delete route: #{e.message}")
      end

      Success()
    rescue Keenetic::ApiError => e
      logger.error("ApplyRouteChanges failed: #{e.message}")
      Failure(error: e.message)
    end

    private

    def transform_route_for_add(route)
      result = {
        interface: route[:interface] || 'Wireguard0',
        comment: route[:comment]
      }

      if route[:host]
        result[:host] = route[:host]
      elsif route[:network]
        if route[:mask]
          cidr = Constants::MASKS.key(route[:mask]) || '32'
          result[:network] = "#{route[:network]}/#{cidr}"
        else
          result[:network] = route[:network]
        end
      end

      result
    end

    def transform_route_for_delete(route)
      if route[:host]
        { host: route[:host] }
      elsif route[:network]
        if route[:mask]
          cidr = Constants::MASKS.key(route[:mask]) || '32'
          { network: "#{route[:network]}/#{cidr}" }
        else
          { network: route[:network] }
        end
      else
        {}
      end
    end
  end
end
