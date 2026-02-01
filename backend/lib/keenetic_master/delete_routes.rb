class KeeneticMaster
  class DeleteRoutes < BaseClass
    def call(routes)
      return Success(empty: true) if routes.empty?

      logger.info("Deleting #{routes.size} routes")
      errors = []

      routes.each do |route|
        route_params = transform_route(route)
        
        begin
          Configuration.keenetic_client.routes.delete(**route_params)
        rescue Keenetic::ApiError => e
          logger.error("Failed to delete route #{route_params}: #{e.message}")
          errors << e.message
        end
      end

      if errors.any?
        Failure(errors: errors, message: "#{errors.size} route(s) failed to delete: #{errors.first}")
      else
        Success(message: "#{routes.size} route(s) deleted successfully")
      end
    end

    private

    def transform_route(route)
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
