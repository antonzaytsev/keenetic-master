require_relative 'a_route_request'

class KeeneticMaster
  class ToggleClientVpn < ARouteRequest
    def call(client_name)
      data = load_data
      return Failure(data) if data.failure?

      vpn_policy = find_policy(data.value!)
      mac = find_client_mac(data.value!, client_name)
      current_client_policy = find_client_policy(data.value!, mac)

      update_client_policy(mac, current_client_policy, vpn_policy)
    end

    private

    def load_data
      # response = Client.new.post_rci({"show": {"sc": {"ip": {"policy": {}}}}})
      # response = Client.new.post_rci({"show": {"sc": {"ip": {"hotspot": {"policy": {}}}}}})

      body = [
        {"show": {"sc": {"ip": {"policy": {}}}}},
        {"show": {"sc": {"ip": {"hotspot": {"host": {}}}}}},
        {"show": {"ip": {"hotspot": {}}}}
      ]

      response = Client.new.post_rci(body)
      Failure(response) if response.code != 200

      data = JSON.parse(response.body)
      Success({}.tap { |result| data.each { |el| result.deep_merge!(el) } })
    end

    # пока что возвращаем статичное значение, возможно стоит выбрать значение из данных
    def find_policy(data)
      'Policy0'
    end

    def find_client_mac(data, client_name)
      client = data.dig('show', 'ip', 'hotspot', 'host').detect do |host|
        host['name'] == client_name || host['hostname'] == client_name
      end
      return false if client.nil?

      client['mac']
    end

    def find_client_policy(data, mac)
      client = data.dig('show', 'sc', 'ip', 'hotspot', 'host').detect do |host|
        host['mac'] == mac
      end
      client['policy']
    end

    def update_client_policy(mac, current_client_policy, vpn_policy)
      policy =
        if current_client_policy
          {no: true}
        else
          vpn_policy
        end

      body = [
        {"webhelp": {"event": {"push": {"data": {"type": "configuration_change", "value": { "url": "/policies/policy-consumers"}}.to_json}}}},
        {"ip": {"hotspot": {"host": {"mac": mac, "permit": true, "policy": policy}}}},
        {"system": {"configuration": {"save": {}}}}
      ]

      response = Client.new.post_rci(body)
      Failure(response) if response.code != 200

      Success()
    end
  end
end
