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
      
      # Handle case where Client returns a Dry::Monads result
      if response.respond_to?(:failure?) && response.failure?
        return Failure(request_failure: response)
      end
      
      return Failure(request_failure: response) if response.code != 200

      result = JSON.parse(response.body).dig(0, 'show', 'sc', 'ip', 'route')
      return Failure(error: "No route data in response") unless result
      
      routes = result.map do |row|
        row.transform_keys(&:to_sym)
      end
      
      Success(routes)
    end
  end
end
