class KeeneticMaster
  class GetAllRoutes < BaseClass
    def call
      routes = Configuration.keenetic_client.routes.all
      # Transform keys to symbols for consistency with existing code
      routes = routes.map { |row| row.transform_keys(&:to_sym) }

      Success(routes)
    rescue Keenetic::AuthenticationError => e
      logger.error("GetAllRoutes: Authentication failed: #{e.message}")
      Failure(error: "Authentication failed: #{e.message}")
    rescue Keenetic::ConnectionError, Keenetic::TimeoutError => e
      logger.error("GetAllRoutes: Connection error: #{e.message}")
      Failure(error: "Failed to connect to router: #{e.message}")
    rescue Keenetic::ApiError => e
      logger.error("GetAllRoutes: API error: #{e.message}")
      Failure(error: "Router request failed: #{e.message}")
    end
  end
end
