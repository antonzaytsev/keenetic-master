require 'yaml'

class KeeneticMaster
  class UpdateDomainRoutes < BaseClass
    PATTERN = "[auto:{website}]"
    GITHUB_META_URL = 'https://api.github.com/meta'

    def call(group_name, interface = nil)
      start = Time.now

      interface = interface.presence || ENV['KEENETIC_VPN_INTERFACE']
      if interface.blank?
        logger.info "Используется дефолтный интерфейс для VPN: 'Wireguard0'"
        interface = 'Wireguard0'
      end

      existing_routes = retrieve_existing_routes(group_name)
      eventual_routes = routes_to_exist(group_name, interface)

      to_delete = (existing_routes - eventual_routes)
      DeleteRoutes.call(to_delete.map { |el| el.slice(:network, :mask) })

      to_add = (eventual_routes - existing_routes)
      add_result = AddRoutes.call(to_add) if to_add.any?
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
        next if row['comment'] !~ /^#{Regexp.escape(PATTERN.sub('{website}', website))}/

        if row['host']
          row['network'] = row['host']
          row['mask'] = Constants::MASKS['32']
          row.delete('host')
        end

        row.slice('network', 'mask', 'comment', 'interface').transform_keys(&:to_sym)
      end
    end

    def routes_to_exist(website, interface)
      return github_ips if website == 'github'

      domains_db = YAML.load_file(ENV.fetch('DOMAINS_FILE'))
      domains = domains_db[website]
      return [] if domains.nil?

      domain_mask = ENV.fetch('DOMAINS_MASK', '32').to_s

      if domains.is_a?(Hash)
        settings_mask = domains.dig('settings', 'mask')
        domain_mask = settings_mask.to_s if settings_mask.present?

        settings_interface = domains.dig('settings', 'interface')
        interface = settings_interface if settings_interface.present?

        domains = domains['domains']
      end

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

          candidate = {
            comment:,
            network:,
            mask:,
            interface:
          }

          next if to_add.any? { |el| el[:network] == candidate[:network] && el[:mask] == candidate[:mask] }

          to_add << candidate
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
            candidate = {
              comment:,
              network:,
              mask:,
              interface:
            }
            next if to_add.any? { |el| el[:network] == candidate[:network] && el[:mask] == candidate[:mask] }

            to_add << candidate
          end
        end
      end

      to_add
    end

    def github_ips
      comment = "#{PATTERN.sub('{website}', 'github')} from meta"

      json = JSON.parse(Typhoeus.get(GITHUB_META_URL).body)
      ip_ranges = json.slice('hooks', 'web', 'api', 'git', 'packages', 'pages', 'importer', 'copilot').values.flatten.reject { |el| el =~ /:/ }.uniq.sort

      to_add = []
      ip_ranges.each do |ip_range|
        network, cidr_notation = ip_range.split('/')
        if cidr_notation == '32'
          network = network.sub(/\d+$/, '0')
          mask = Constants::MASKS.fetch('24')
        else
          mask = Constants::MASKS.fetch(cidr_notation)
        end

        next if to_add.any? { |el| el[:network] == network && el[:mask] == mask }

        to_add << {
          comment:,
          network: network,
          mask: mask,
        }
      end

      to_add
    end
  end
end
