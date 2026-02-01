class KeeneticMaster
  class ToggleClientPolicy < BaseClass
    def call(client_name, policy_name = "!WG1")
      client = Configuration.keenetic_client

      # Get policies and hosts
      policies = client.hotspot.policies
      hosts = client.hotspot.hosts

      # Find target policy by description
      vpn_policy = find_policy(policies, policy_name)
      
      # Find client MAC by name
      client_mac = find_client_mac(hosts, client_name)
      return client_mac if client_mac.failure?

      mac = client_mac.value!
      
      # Find current policy for this client
      current_policy = find_current_policy(hosts, mac)

      # Toggle: remove if has policy, set if doesn't
      if current_policy
        client.hotspot.set_host_policy(mac: mac, policy: nil)
        Success(message: "VPN disabled for client")
      else
        client.hotspot.set_host_policy(mac: mac, policy: vpn_policy)
        Success(message: "VPN enabled for client")
      end
    rescue Keenetic::ApiError => e
      logger.error("ToggleClientPolicy failed: #{e.message}")
      Failure(error: e.message)
    end

    private

    def find_policy(policies, policy_name)
      policies.each do |policy_key, policy_data|
        return policy_key if policy_data['description'] == policy_name
      end
      policies.keys.first
    end

    def find_client_mac(hosts, client_name)
      # hosts from hotspot.hosts includes both config and runtime data
      host = hosts.detect do |h|
        h['name'] == client_name || h['hostname'] == client_name
      end
      
      return Failure(error: "Cannot find client by name: #{client_name}") if host.nil?
      Success(host['mac'])
    end

    def find_current_policy(hosts, mac)
      host = hosts.detect { |h| h['mac'] == mac }
      host&.dig('policy')
    end
  end
end
