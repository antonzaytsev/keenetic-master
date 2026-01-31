class KeeneticMaster
  class ToggleClientPolicy < BaseClass
    def call(client_name, policy_name = "!WG1")
      data_result = load_data
      return Failure(data) if data_result.failure?

      data = data_result.value!

      vpn_policy = find_policy(data, policy_name)
      client_mac = find_client_mac(data, client_name)
      return client_mac if client_mac.failure?

      current_client_policy = find_client_policy(data, client_mac.value!)

      update_client_policy(client_mac.value!, current_client_policy, vpn_policy)
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

    def find_policy(data, policy_name)
      policies = data.dig('show', 'sc', 'ip', 'policy')

      policies.each do |policy_key, policy_data|
        return policy_key if policy_data['description'] == policy_name
      end

      policies.keys[0]
    end

    def find_client_mac(data, client_name)
      client = data.dig('show', 'ip', 'hotspot', 'host').detect do |host|
        host['name'] == client_name || host['hostname'] == client_name
      end
      return Failure(error: 'cant find client by name') if client.nil?

      Success(client['mac'])
    end

    def find_client_policy(data, mac)
      client = data.dig('show', 'sc', 'ip', 'hotspot', 'host').detect { |host| host['mac'] == mac }
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
      return Failure(response) if response.code != 200

      Success(message: "Клиенту #{current_client_policy ? "выключен" : "включен"} VPN")
    end
  end
end
