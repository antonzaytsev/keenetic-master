require 'typhoeus'
require 'json'

class KeeneticMaster
  class GetAllRoutes < BaseClass
    def call
      body = [
        # {"whoami": {}},
        # {"show": {"last-change": {}}},
        # {"show": {"sc": {"user": {}}}},
        {"show": {"sc": {"ip": {"route": {}}}}},
        # {"show": {"ip": {"route": {}}}},
        # {"show": {"ipv6": {"route": {}}}},
        # {"show": {"sc": {"interface": {"trait": "Ip"}}}},
        # {"show": {"interface": {"details": "yes", "trait": "Ip"}}},
        # {"show": {"sc": {"interface": {"ipoe": {"parent": ""}}}}}
      ]

      response = Client.post_rci(body)

      binding.pry

      # Handle case where Client returns a Dry::Monads Failure (from handle_error)
      if response.respond_to?(:failure?) && response.failure?
        # Extract error message from the Failure
        failure = response.failure
        error_msg = if failure.is_a?(Hash)
          # Prefer message (from handle_error) over error
          # handle_error returns: {message: "...", error: <exception>, backtrace: [...]}
          failure[:message] || (failure[:error].respond_to?(:message) ? failure[:error].message : failure[:error].to_s) || "Failed to connect to router"
        else
          failure.to_s
        end

        logger.error("GetAllRoutes: Client.post_rci returned failure: #{error_msg}")
        # Return the Failure with a clear error message
        return Failure(error: error_msg)
      end

      # Handle case where response is not a Typhoeus response (shouldn't happen, but be safe)
      unless response.respond_to?(:code)
        return Failure(error: "Unexpected response type from router: #{response.class}")
      end

      return Failure(error: "Router request failed with code #{response.code}", request_failure: response) if response.code != 200

      begin
        result = JSON.parse(response.body).dig(0, 'show', 'sc', 'ip', 'route')
        return Failure(error: "No route data in response") unless result

        routes = result.map do |row|
          row.transform_keys(&:to_sym)
        end

        Success(routes)
      rescue JSON::ParserError => e
        Failure(error: "Failed to parse router response: #{e.message}")
      rescue => e
        Failure(error: "Unexpected error processing routes: #{e.message}")
      end
    end
  end
end
