require_relative 'mutate_route_request'
require 'json'

class KeeneticMaster
  class DeleteRoutes < MutateRouteRequest
    def call(routes)
      return Success(empty: true) if routes.empty?

      modified_routes = routes.map do |route|
        # Handle both host and network/mask formats
        # Keenetic uses :host for single IP routes (/32), :network/:mask for network routes
        if route[:host]
          processed = { host: route[:host] }
        else
          processed = process_route(route)
        end
        processed[:comment] = route[:comment] if route[:comment]
        processed[:interface] = route[:interface] if route[:interface]
        processed[:no] = true
        processed
      end

      logger.info("Sending delete request for #{modified_routes.size} routes")
      logger.debug("Routes to delete: #{modified_routes.inspect}")

      response = Client.new.post_rci(build_body_routes(modified_routes))
      return Failure(response) if response.code != 200

      # Parse response to check if deletion was successful
      errors = []
      begin
        parsed_response = JSON.parse(response.body)
        ip_responses = parsed_response.select { |el| el['ip'] && el['ip']['route'] }
        
        logger.debug("Router response: #{parsed_response.inspect}")
        
        # Check each route deletion response
        ip_responses.each do |ip_response|
          route_status = ip_response.dig('ip', 'route', 'status')
          if route_status.is_a?(Array)
            route_status.each do |status|
              if status['status'] == 'error'
                error_msg = status['message'] || 'Unknown error'
                logger.error("Route deletion error: #{error_msg}")
                errors << error_msg
              end
            end
          end
        end
      rescue JSON::ParserError => e
        logger.warn("Failed to parse delete response: #{e.message}")
      end

      if errors.any?
        Failure(errors: errors, message: "#{errors.size} route(s) failed to delete: #{errors.first}")
      else
        Success()
      end
    end
  end
end
