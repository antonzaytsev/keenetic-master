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
      return Failure(request_failure: response) if response.code != 200

      result = JSON.parse(response.body).dig(0, 'show', 'sc', 'ip', 'route')
      # result = JSON.parse(response.body).detect { |el| el['ip'] }.dig('ip', 'route', 'status', 0)
      #
      # if result['status'] == 'error'
      #   return Failure(result['status'] => result['message'])
      # end
      #
      Success(message: result)
    end
  end
end
