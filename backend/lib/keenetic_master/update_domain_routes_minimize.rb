require 'yaml'
require 'resolv'
require 'json'
require_relative '../database'
require_relative '../models'

class KeeneticMaster
  class UpdateDomainRoutesMinimize < BaseClass
    PATTERN = "[auto:{website}]"

    def call(groups, delete_missing: true)
      start_time = Time.now

      logger.info("Starting domain routes update for #{groups.size} groups")

      begin
        routes_to_update = collect_routes_to_update(groups, delete_missing)
        eventual_routes_amount = count_eventual_routes(groups)

        save_request_dump(routes_to_update)
        apply_changes(routes_to_update)

        log_completion(groups.size, routes_to_update.size, eventual_routes_amount, start_time)
        Success(
          touched: routes_to_update.size,
          eventually: eventual_routes_amount,
          message: build_success_message(groups.size, routes_to_update.size, eventual_routes_amount, start_time)
        )

      rescue StandardError => e
        handle_error(e, "Domain routes update")
      end
    end

    private

    def collect_routes_to_update(groups, delete_missing)
      routes_to_update = []
      existing_routes = fetch_existing_routes

      progress_bar = ProgressBar.new(groups.size + 1)

      groups.each do |group_name|
        existing_routes_for_group = filter_existing_routes_for_group(existing_routes, group_name)
        eventual_routes = routes_to_exist(group_name)

        routes_to_update.concat(routes_to_remove(existing_routes_for_group, eventual_routes))
        routes_to_update.concat(routes_to_add(eventual_routes, existing_routes_for_group))

        progress_bar.increment!
      end

      routes_to_update.concat(orphaned_routes_to_remove(existing_routes, groups)) if delete_missing
      progress_bar.increment!

      routes_to_update
    end

    def fetch_existing_routes
      result = GetAllRoutes.new.call
      return result.value![:message] if result.success?

      logger.error("Failed to fetch existing routes: #{result.failure}")
      []
    end

    def filter_existing_routes_for_group(existing_routes, group_name)
      pattern_regex = Regexp.escape(PATTERN.sub('{website}', group_name))

      existing_routes.filter_map do |route|
        next unless route[:comment] =~ /^#{pattern_regex}/

        standardize_route(route)
      end
    end

    def standardize_route(route)
      route = route.dup

      if route[:host]
        route[:network] = route[:host]
        route[:mask] = Constants::MASKS['32']
        route.delete(:host)
      end

      route.slice(:network, :mask, :comment, :interface)
    end

    def routes_to_remove(existing_routes, eventual_routes)
      (existing_routes - eventual_routes).map do |route|
        process_route(route).merge(comment: route[:comment], no: true)
      end
    end

    def routes_to_add(eventual_routes, existing_routes)
      (eventual_routes - existing_routes).map do |route|
        prepare_route_for_addition(route)
      end
    end

    def prepare_route_for_addition(route)
      route[:gateway] ||= ''
      route[:auto] = true unless route.key?(:auto)
      route[:reject] = false unless route.key?(:reject)

      process_host(route,
        host: route[:host],
        network: route[:network],
        mask: route[:mask]
      )

      route.dup
    end

    def orphaned_routes_to_remove(existing_routes, websites)
      existing_routes.filter_map do |existing_route|
        website = extract_website_from_comment(existing_route[:comment])
        next if website.nil? || websites.include?(website)

        process_route(existing_route.dup).merge(comment: existing_route[:comment], no: true)
      end
    end

    def extract_website_from_comment(comment)
      comment.match(/^\[auto:([a-z]*)\]/)&.captures&.first
    end

    def count_eventual_routes(websites)
      websites.sum { |website| routes_to_exist(website).size }
    end

    def save_request_dump(routes_to_update)
      dump_dir = Configuration.request_dumps_dir
      File.write(File.join(dump_dir, 'request.json'), routes_to_update.to_json)
    end

    def apply_changes(routes_to_update)
      ApplyRouteChanges.call(routes_to_update)
    end

    def log_completion(websites_count, touched_routes, eventual_routes, start_time)
      elapsed_time = (Time.now - start_time).round(2)
      message = build_success_message(websites_count, touched_routes, eventual_routes, start_time)
      logger.info(message)
    end

    def build_success_message(websites_count, touched_routes, eventual_routes, start_time)
      elapsed_time = (Time.now - start_time).round(2)
      "Успешно обработано групп: #{websites_count}. " \
      "Затронуто роутов: #{touched_routes}. " \
      "Роутов итого: #{eventual_routes}. " \
      "Время: #{elapsed_time}сек"
    end

    def routes_to_exist(website, interface = nil)
      domains = load_domains_for_website(website)
      return [] if domains.nil?

      settings = extract_settings_from_domains(domains)
      domains = extract_domains_list(domains, website)

      domain_mask = settings[:mask] || Configuration.domains_mask
      interfaces = settings[:interfaces]&.split(',') || determine_interfaces(interface)

      resolve_domains_to_routes(domains, website, domain_mask, interfaces)
    end

    def load_domains_for_website(website)
      group = DomainGroup.find(name: website)
      return nil unless group
      
      group.to_hash
    end

    def extract_settings_from_domains(domains)
      return {} unless domains.is_a?(Hash)

      settings = domains.dig('settings') || {}
      {
        mask: settings['mask']&.to_s,
        interfaces: settings['interfaces']
      }
    end

    def extract_domains_list(domains, website)
      domains = domains['domains'] if domains.is_a?(Hash)
      domains
    end

    def determine_interfaces(interface_override)
      interfaces = interface_override&.strip || Configuration.vpn_interfaces.join(',')

      if interfaces.blank?
        logger.info "Используется дефолтный интерфейс для VPN: 'Wireguard0'"
        interfaces = 'Wireguard0'
      end

      interfaces.split(',').map { |iface| CorrectInterface.call(iface.strip) }
    end

    def resolve_domains_to_routes(domains, website, domain_mask, interfaces)
      routes = []
      dns_resolvers = create_dns_resolvers

      domains.uniq.each do |domain|
        if valid_ip_or_mask?(domain)
          routes.concat(create_routes_for_ip_range(domain, website, interfaces))
        else
          routes.concat(resolve_domain_to_routes(domain, website, domain_mask, interfaces, dns_resolvers))
        end
      end

      routes.uniq
    end

    def create_dns_resolvers
      Configuration.dns_servers.map { |nameserver| Resolv::DNS.new(nameserver: nameserver) }
    end

    def create_routes_for_ip_range(ip_range, website, interfaces)
      network, mask, comment = parse_ip_range(ip_range, website)

      create_routes_for_network(network, mask, comment, interfaces)
    end

    def parse_ip_range(ip_range, website)
      if ip_range.include?('/')
        network, cidr_notation = ip_range.split('/')
        mask = Constants::MASKS.fetch(cidr_notation)
        comment = "#{PATTERN.sub('{website}', website)} Direct Range"
      elsif ip_range =~ Resolv::IPv4::Regex
        network = ip_range.sub(/\.\d+$/, '.0')
        mask = '255.255.255.0'
        comment = "#{PATTERN.sub('{website}', website)} Direct IP"
      else
        raise ArgumentError, "Unsupported IP format: #{ip_range}"
      end

      [network, mask, comment]
    end

    def resolve_domain_to_routes(domain, website, domain_mask, interfaces, dns_resolvers)
      routes = []
      comment = "#{PATTERN.sub('{website}', website)} #{domain}"
      mask = Constants::MASKS.fetch(domain_mask)

      addresses = resolve_domain_addresses(domain, dns_resolvers)

      addresses.each do |address|
        addr_string = address.address.to_s
        next if addr_string.start_with?('127.')

        network = calculate_network(addr_string, domain_mask)
        routes.concat(create_routes_for_network(network, mask, comment, interfaces))
      end

      routes
    end

    def resolve_domain_addresses(domain, dns_resolvers)
      dns_resolvers.flat_map do |resolver|
        resolver.getresources(domain, Resolv::DNS::Resource::IN::A)
      rescue Resolv::ResolvError => e
        logger.warn("Failed to resolve #{domain}: #{e.message}")
        []
      end
    end

    def calculate_network(address, domain_mask)
      if domain_mask == '24'
        address.sub(/\.\d+$/, '.0')
      else
        address
      end
    end

    def create_routes_for_network(network, mask, comment, interfaces)
      routes = []

      interfaces.each do |interface|
        candidate = {
          comment: comment,
          network: network,
          mask: mask,
          interface: interface
        }

        next if routes.any? { |route| routes_equivalent?(route, candidate) }

        routes << candidate
      end

      routes
    end

    def routes_equivalent?(route1, route2)
      route1.slice(:network, :mask, :interface) == route2.slice(:network, :mask, :interface)
    end

    def valid_ip_or_mask?(domain)
      domain.match?(/^[\d.\/]+$/)
    end

    # Route processing helpers (moved from MutateRouteRequest)
    def process_host(route, host:, network:, mask:)
      if host && host =~ /\//
        network, cidr_notation = host.split('/')
        mask = Constants::MASKS.fetch(cidr_notation)
        host = nil
      end

      if host
        route[:host] = host
      else
        route[:network] = network
        route[:mask] = mask
      end
    end

    def process_route(route)
      if route[:host] && route[:host] =~ /\//
        route[:network], cidr_notation = route[:host].split('/')
        route[:mask] = Constants::MASKS.fetch(cidr_notation)
        route.delete(:host)
      end

      if route[:host]
        route.slice(:host)
      else
        route.slice(:network, :mask)
      end
    end
  end
end
