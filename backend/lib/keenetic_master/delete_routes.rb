require_relative 'mutate_route_request'
require 'json'

class KeeneticMaster
  class DeleteRoutes < MutateRouteRequest
    def call(routes)
      return Success(empty: true) if routes.empty?

      modified_routes = routes.map do |route|
        processed = process_route(route)
        processed[:comment] = route[:comment] if route[:comment]
        processed[:interface] = route[:interface] if route[:interface]
        processed[:no] = true
        processed
      end

      response = Client.new.post_rci(build_body_routes(modified_routes))
      return Failure(response) if response.code != 200

      # Parse response to check if deletion was successful
      begin
        parsed_response = JSON.parse(response.body)
        ip_responses = parsed_response.select { |el| el['ip'] && el['ip']['route'] }
        
        # Check each route deletion response
        ip_responses.each do |ip_response|
          route_status = ip_response.dig('ip', 'route', 'status')
          if route_status.is_a?(Array)
            route_status.each do |status|
              if status['status'] == 'error'
                logger.warn("Route deletion error: #{status['message']}")
              end
            end
          end
        end
      rescue JSON::ParserError => e
        logger.warn("Failed to parse delete response: #{e.message}")
      end

      Success()
    end
  end
end
