require 'yaml'

class KeeneticMaster
  class UpdateDomainRoutesMinimize < MutateRouteRequest
    PATTERN = "[auto:{website}]"
    GITHUB_META_URL = 'https://api.github.com/meta'

    def call(websites, delete_missing: true)
      start = Time.now

      routes_to_update = []
      eventual_routes_amount = 0

      existing_routes = GetAllRoutes.new.call.value![:message]

      websites.each do |group_name|
        existing_routes_standardized = existing_routes.filter_map do |row|
          next if row[:comment] !~ /^#{Regexp.escape(PATTERN.sub('{website}', group_name))}/

          row = row.dup

          if row[:host]
            row[:network] = row[:host]
            row[:mask] = Constants::MASKS['32']
            row.delete(:host)
          end

          row.slice(:network, :mask, :comment, :interface)
        end
        eventual_routes = routes_to_exist(group_name)
        eventual_routes_amount += eventual_routes.size

        # to remove
        routes_to_update += (existing_routes_standardized - eventual_routes).map do |route|
          process_route(route).merge(comment: route[:comment], no: true).dup
        end

        # to add
        routes_to_update += (eventual_routes - existing_routes_standardized).map do |route|
          route[:gateway] ||= ''
          route[:auto] = true unless route.key?(:auto)
          route[:reject] = false unless route.key?(:reject)

          process_host(route, host: route[:host], network: route[:network], mask: route[:mask])

          route.dup
        end
      end

      if delete_missing
        existing_routes.each do |existing_route|
          website = existing_route[:comment].match(/^\[auto:([a-z]*)\]/)[1]
          next if websites.include?(website)

          routes_to_update << process_route(existing_route.dup).merge(comment: existing_route[:comment], no: true)
        end
      end

      ApplyRouteChanges.call(routes_to_update)

      message = "Успешно обработано групп: #{websites.size}. Затронуто роутов: #{routes_to_update.size}. Роутов итого: #{eventual_routes_amount}. Время: #{(Time.now - start).round(2)}сек"
      logger.info(message)
      Success(touched: routes_to_update.size, eventually: eventual_routes_amount, message:)
    end

    private

    def routes_to_exist(website, interface = nil)
      domains = YAML.load_file(ENV.fetch('DOMAINS_FILE'))[website]
      domains = github_ips(domains) if website == 'github'
      return [] if domains.nil?

      domain_mask = ENV.fetch('DOMAINS_MASK', '32').to_s
      interface = interface.presence || ENV['KEENETIC_VPN_INTERFACE'] || ENV['KEENETIC_VPN_INTERFACES']

      if domains.is_a?(Hash)
        settings_mask = domains.dig('settings', 'mask')
        domain_mask = settings_mask.to_s if settings_mask.present?

        settings_interface = domains.dig('settings', 'interfaces')
        interface = settings_interface if settings_interface.present?

        domains = domains['domains']
      end

      if interface.blank?
        logger.info "Используется дефолтный интерфейс для VPN: 'Wireguard0'"
        interface = 'Wireguard0'
      end
      interfaces = interface.split(',').map { |interface| correct_interface_id(interface.strip)}

      to_add = []

      dns_servers = ENV.fetch('DNS_SERVERS', nil)&.split(',') || ['1.1.1.1', '8.8.8.8']
      dns_resolvers = dns_servers.map { |nameserver| Resolv::DNS.new(nameserver: ) }
      domains.uniq.each do |domain|
        if valid_ip_or_mask?(domain)
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

    def valid_ip_or_mask?(domain)
      domain =~ /^[\d.\/]+$/
    end
  end
end
