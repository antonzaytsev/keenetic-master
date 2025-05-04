require 'yaml'

class KeeneticMaster
  class UpdateDomainRoutes < BaseClass
    PATTERN = "[auto:{website}]"
    GITHUB_META_URL = 'https://api.github.com/meta'

    def call(group_name, default_interface = nil)
      start = Time.now

      existing_routes = retrieve_existing_routes(group_name)
      eventual_routes = routes_to_exist(group_name, default_interface)

      to_delete = existing_routes - eventual_routes
      to_delete = [] if ENV['DELETE_ROUTES'] == 'false'
      DeleteRoutes.call(to_delete.map { |el| el.slice(:network, :mask) }) if to_delete.any?

      to_add = eventual_routes - existing_routes
      add_result = AddRoutes.call(to_add)
      if add_result.failure?
        return add_result
      end

      message = "Успешно обработана группа `#{group_name}`. Добавлено: #{to_add.size}, удалено: #{to_delete.size}, в итоге: #{eventual_routes.size}. Время: #{(Time.now - start).round(2)}s"
      logger.info(message)

      Success(added: to_add.size, deleted: to_delete.size, eventually: eventual_routes.size, message:)
    end

    private

    def retrieve_existing_routes(website)
      GetAllRoutes.new.call.value![:message].filter_map do |row|
        next if row[:comment] !~ /^#{Regexp.escape(PATTERN.sub('{website}', website))}/

        if row[:host]
          row[:network] = row[:host]
          row[:mask] = Constants::MASKS['32']
          row.delete(:host)
        end

        row.slice(:network, :mask, :comment, :interface)
      end
    end

    def routes_to_exist(website, interface)
      domains = YAML.load_file(ENV.fetch('DOMAINS_FILE'))[website]

      domain_mask = ENV.fetch('DOMAINS_MASK', '32').to_s
      interface = interface.presence || ENV['KEENETIC_VPN_INTERFACE'] || ENV['KEENETIC_VPN_INTERFACES']

      if domains.is_a?(Hash)
        settings_mask = domains.dig('settings', 'mask')
        domain_mask = settings_mask.to_s if settings_mask.present?

        settings_interface = domains.dig('settings', 'interfaces')
        interface = settings_interface if settings_interface.present?

        domains = domains['domains']
      end

      domains = github_ips(domains) if website == 'github'
      return [] if domains.nil?

      if interface.blank?
        logger.info "Используется дефолтный интерфейс для VPN: 'Wireguard0'"
        interface = 'Wireguard0'
      end
      interfaces = interface.split(',').map { |interface| correct_interface_id(interface.strip)}

      to_add = []

      dns_servers = ENV.fetch('DNS_SERVERS', nil)&.split(',') || ['1.1.1.1', '8.8.8.8']
      dns_resolvers = dns_servers.map { |nameserver| Resolv::DNS.new(nameserver: ) }
      domains.uniq.each do |domain|
        if domain =~ /^[\d.\/]+$/
          if domain =~ /\//
            comment = "#{PATTERN.sub('{website}', website)} Direct Range"
            network, cidr_notation = domain.split('/')
            mask = Constants::MASKS.fetch(cidr_notation)
          elsif domain =~ Resolv::IPv4::Regex
            comment = "#{PATTERN.sub('{website}', website)} Direct IP"
            network = domain.sub(/\.\d+$/, '.0')
            mask = '255.255.255.0'
          else
            raise 'unsupported'
          end

          interfaces.each do |interface|
            candidate = {
              comment:,
              network:,
              mask:,
              interface:
            }

            next if to_add.any? { |el| el.slice(:network, :mask, :interface) == candidate.slice(:network, :mask, :interface) }

            to_add << candidate
          end
        else
          comment = "#{PATTERN.sub('{website}', website)} #{domain}"

          mask = Constants::MASKS.fetch(domain_mask)

          addresses = dns_resolvers.flat_map { |resolver| resolver.getresources(domain, Resolv::DNS::Resource::IN::A) }
          addresses.each do |address|
            addr = address.address.to_s
            next if addr =~ /^127\./

            network =
              if domain_mask == '24'
                address.address.to_s.sub(/\.\d+$/, '.0')
              else
                address.address.to_s
              end

            interfaces.each do |interface|
              candidate = {
                comment:,
                network:,
                mask:,
                interface:
              }
              next if to_add.any? { |el| el.slice(:network, :mask, :interface) == candidate.slice(:network, :mask, :interface) }

              to_add << candidate
            end
          end
        end
      end

      to_add
    end

    def github_ips(sections = [])
      sections = ['hooks', 'web', 'api', 'git', 'packages', 'pages', 'importer', 'copilot'] if sections.blank?
      github_meta_response = Typhoeus.get(GITHUB_META_URL).body
      JSON
        .parse(github_meta_response)
        .slice(*sections)
        .values.flatten.reject { |el| el =~ /:/ }.uniq.sort
    end

    def correct_interface_id(interface)
      return interface if existing_interfaces.failure?

      existing_interfaces_list = existing_interfaces.value!
      return interface if existing_interfaces_list.key?(interface)

      existing_interface = existing_interfaces_list.values.detect { |data| data['description'] == interface }
      return interface if existing_interface.nil?

      existing_interface['id']
    end

    def existing_interfaces
      @existing_interfaces ||= KeeneticMaster.interface
    end
  end
end
