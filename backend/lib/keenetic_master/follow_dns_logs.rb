require_relative '../database'
require_relative '../models'
require 'typhoeus'
require 'json'

class KeeneticMaster
  class FollowDnsLogs < BaseClass
    WAIT = 10
    DOMAINS_FILE_CACHE_TTL = 5
    API_TIMEOUT = 30

    def self.call(base_api_url = nil)
      new.call(base_api_url)
    end

    def initialize
      super
      @last_fetch_time = nil
    end

    def call(base_api_url = nil)
      @base_api_url = base_api_url || ExternalServices::DnsServer.search_url

      unless @base_api_url.present?
        puts "DNS_SERVER_URL is not configured"
        return
      end

      if follow_dns.blank?
        puts "Нет ни одной группы в базе данных с параметром follow_dns"
        return
      end

      logger.info "Начато слежение за DNS логами через API: #{@base_api_url}"

      while true
        begin
          logs_data = fetch_dns_logs
          process_api_logs(logs_data)
          update_last_fetch_time
        rescue => e
          logger.error "Ошибка при получении DNS логов: #{e.message}.\n#{e.backtrace}"
        end

        sleep WAIT
      end

    rescue Interrupt
      logger.info "Слежение за DNS логами прервано"
    end

    private

    def update_last_fetch_time
      @last_fetch_time = Time.now
      logger.info "Updated last fetch time to #{@last_fetch_time.utc.strftime('%Y-%m-%dT%H:%M:%SZ')}"
    end

    def fetch_dns_logs
      since_time = @last_fetch_time || (Time.now - 10 * 60) # Default to 10 minutes ago
      since_param = since_time.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
      api_url = "#{@base_api_url}?since=#{since_param}"

      logger.info "Запрос DNS логов с #{api_url}"

      response = Typhoeus.get(api_url,
        timeout: API_TIMEOUT,
        connecttimeout: 10,
        headers: {
          "Accept" => "application/json",
          "User-Agent" => "KeeneticMaster/#{KeeneticMaster::VERSION}"
        }
      )

      unless response.success?
        logger.error "Ошибка запроса к API: HTTP #{response.code} - #{response.body}"
        return []
      end

      JSON.parse(response.body).dig('results')

    rescue JSON::ParserError => e
      logger.error "Ошибка парсинга JSON ответа: #{e.message}"
      []
    end

    def process_api_logs(logs_data)
      return if logs_data.empty?

      logger.debug "Обработка #{logs_data.size} записей DNS логов"

      routes_to_update = []
      processed_domains = {}

      logs_data.each do |entry|
        process_log_entry(entry, routes_to_update, processed_domains)
      end

      apply_route_updates(routes_to_update, processed_domains)
    end

    def process_log_entry(entry, routes_to_update, processed_domains)
      # Handle both string (line from file) and hash (API response) formats
      group = case entry
      when String
        JSON.parse(entry) rescue nil
      when Hash
        entry
      else
        nil
      end

      ip_addresses = group['answers']&.map(&:last) || []

      return if group.nil? || ip_addresses.blank?

      requested_domain = group['request']['query'][0..-2]
      domain_matched = false

      follow_dns.each do |website, data|
        data[:domains].each do |domain|
          if requested_domain == domain || requested_domain =~ /\.#{Regexp.escape(domain)}$/
            domain_matched = true
            routes_count = add_routes_for_domain(group, website, requested_domain, data, routes_to_update)

            # Log the processing event
            DnsProcessingLog.log_processing_event(
              action: 'processed',
              domain: requested_domain,
              group_name: website,
              routes_count: routes_count,
              ip_addresses: ip_addresses,
              comment: "[auto:#{website}] #{requested_domain}"
            )

            processed_domains[requested_domain] ||= { website: website, routes_count: 0 }
            processed_domains[requested_domain][:routes_count] += routes_count
          end
        end
      end

      # Log domains that didn't match any follow_dns domains
      unless domain_matched
        DnsProcessingLog.log_processing_event(
          action: 'skipped',
          domain: requested_domain,
          group_name: 'none',
          routes_count: 0,
          ip_addresses: ip_addresses,
          comment: 'No matching follow_dns domain found'
        )
      end
    end

    def add_routes_for_domain(group, website, requested_domain, data, routes_to_update)
      routes_count = 0

      group['answers'].each do |answer|
        ip_address = answer.last
        data[:interfaces].each do |interface|
          route = {
            network: ip_address.sub(/\.\d+$/, '.0'),
            mask: Constants::MASKS.fetch('24'),
            interface: CorrectInterface.call(interface),
            comment: "[auto:#{website}] #{requested_domain}",
            auto: true
          }
          routes_to_update << route
          routes_count += 1
        end
      end

      routes_count
    end

    def apply_route_updates(routes_to_update, processed_domains)
      logger.info "routes_to_update: #{routes_to_update.size}"
      return if routes_to_update.blank?

      result = ApplyRouteChanges.call(routes_to_update)

      if result.success?
        processed_domains.each do |domain, info|
          DnsProcessingLog.log_processing_event(
            action: 'added',
            domain: domain,
            group_name: info[:website],
            routes_count: info[:routes_count],
            comment: "Successfully added #{info[:routes_count]} routes"
          )
        end
        logger.info "Successfully applied #{routes_to_update.size} route changes"
      else
        # Log failed route additions
        processed_domains.each do |domain, info|
          DnsProcessingLog.log_processing_event(
            action: 'error',
            domain: domain,
            group_name: info[:website],
            routes_count: 0,
            comment: "Failed to add routes: #{result.failure}"
          )
        end
        logger.error "Failed to apply route changes: #{result.failure}"
      end
    end

    def logger(_ = nil)
      @logger ||= create_logger(STDOUT)
    end

    def follow_dns
      if @follow_dns && @follow_dns[:cached_at] && @follow_dns[:cached_at] > (Time.now - DOMAINS_FILE_CACHE_TTL)
        return @follow_dns[:websites]
      end

      websites = {}

      # Find domain groups that have follow_dns domains
      DomainGroup.all.each do |group|
        follow_dns_domains = group.domains_dataset.where(type: 'follow_dns').map(:domain)
        next if follow_dns_domains.empty?

        interfaces = group.interfaces_list.presence || ENV['KEENETIC_VPN_INTERFACES']&.split(',')&.map(&:strip) || ['Wireguard0']

        websites[group.name] = {
          domains: follow_dns_domains,
          interfaces: interfaces
        }
      end

      logger.debug("Updated list of monitored domains")
      logger.debug(websites)

      @follow_dns = {
        cached_at: Time.now,
        websites: websites
      }

      websites
    end
  end
end
