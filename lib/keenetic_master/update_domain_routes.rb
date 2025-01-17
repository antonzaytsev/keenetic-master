require 'yaml'

class KeeneticMaster
  class UpdateDomainRoutes < BaseClass
    PATTERN = "[auto:{website}]"
    GITHUB_META_URL = 'https://api.github.com/meta'

    def call(website)
      start = Time.now

      existing_routes = retrieve_existing_routes(website)
      eventual_routes = routes_to_exist(website)

      to_delete = (existing_routes - eventual_routes)
      # to_delete.each do |params|
      #   DeleteRoute.call(**params.slice(:host, :network, :mask))
      # end
      DeleteRoutes.call(to_delete.map { |el| el.slice(:network, :mask) })
      # DeleteRoutes.call(to_delete.map { |el| el.slice(:host, :network, :mask) })

      to_add = (eventual_routes - existing_routes)
      # to_add.each do |params|
      #   AddRoute.call(**params)
      # end
      AddRoutes.call(to_add) if to_add.any?

      logger.info("Successfully processed `#{website}`. Added: #{to_add.size}, Deleted: #{to_delete.size}, Eventually: #{eventual_routes.size}. Time: #{(Time.now - start).round(2)}s")

      Success(added: to_add.size, deleted: to_delete.size, eventually: eventual_routes.size)
    end

    private

    def retrieve_existing_routes(website)
      GetAllRoutes.new.call.value![:message].filter_map do |row|
        next if row['comment'] !~ /^#{Regexp.escape(PATTERN.sub('{website}', website))}/

        if row['host']
          row['network'] = row['host']
          row['mask'] = MASKS['32']
          row.delete('host')
        end

        row.slice('network', 'mask', 'comment').transform_keys(&:to_sym)
      end
    end

    def routes_to_exist(website)
      return github_ips if website == 'github'

      domains_db = YAML.load_file(ENV.fetch('DOMAINS_FILE'))
      domains = domains_db[website].uniq
      return if domains.nil?

      to_add = []

      dns_resolver = Resolv::DNS.new(nameserver: ['1.1.1.1', '8.8.8.8'])
      domains.each do |domain|
        if domain =~ /^[\d.\/]+$/
          if domain =~ /\//
            comment = "#{PATTERN.sub('{website}', website)} Direct Range"
            network, cidr_notation = domain.split('/')
            mask = MASKS.fetch(cidr_notation)
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
          }

          if to_add.none? { |el| el[:network] == candidate[:network] && el[:mask] == candidate[:mask] }
            to_add << candidate
          end
        end

        comment = "#{PATTERN.sub('{website}', website)} #{domain}"

        addresses = dns_resolver.getresources(domain, Resolv::DNS::Resource::IN::A)
        addresses.each do |address|
          addr = address.address.to_s
          next if addr =~ /^127\./

          candidate = {
            comment:,
            network: address.address.to_s.sub(/\.\d+$/, '.0'),
            mask: '255.255.255.0',
          }
          next if to_add.any? { |el| el[:network] == candidate[:network] && el[:mask] == candidate[:mask] }

          to_add << candidate
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
          mask = MASKS.fetch('24')
        else
          mask = MASKS.fetch(cidr_notation)
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
