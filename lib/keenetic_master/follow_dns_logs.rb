require_relative 'mutate_route_request'
require_relative '../database'
require_relative '../models'

class KeeneticMaster
  class FollowDnsLogs < MutateRouteRequest
    WAIT = 1
    DOMAINS_FILE_CACHE_TTL = 5

    def call(dns_file)
      if !File.exist?(dns_file) || !File.readable?(dns_file)
        puts "Не указаны или недоступен файл в переменной окружения DNS_LOGS_PATH `#{dns_file}`"
        return
      end

      if follow_dns.blank?
        puts "Нет ни одной группы в базе данных с параметром follow_dns"
        return
      end

      last_position = File.size(dns_file)

      while true
        current_size = File.size(dns_file)
        if current_size == last_position
          sleep WAIT
          next
        end

        # If file was truncated, reset position
        if current_size < last_position
          last_position = 0
          sleep WAIT
          next
        end

        # Read only new content
        File.open(dns_file, 'r') do |file|
          file.seek(last_position)
          new_content = file.read
          if new_content.empty?
            sleep WAIT
            next
          end

          process_logs(new_content)
        end
        last_position = current_size

        sleep WAIT
      end

    rescue Interrupt
    end

    private

    def process_logs(new_content)
      routes_to_update = []

      new_content.lines.each do |line|
        group = JSON.parse(line) rescue nil
        next if group.nil? || group['ip_addresses'].blank?

        requested_domain = group['request']['query'][0..-2]

        follow_dns.each do |website, data|
          data[:domains].each do |domain|
            next if requested_domain != domain && requested_domain !~ /\.#{Regexp.escape(domain)}$/

            group['ip_addresses'].each do |ip_address|
              data[:interfaces].each do |interface|
                routes_to_update << {
                  network: ip_address.sub(/\.\d+$/, '.0'),
                  mask: Constants::MASKS.fetch('24'),
                  interface: CorrectInterface.call(interface),
                  comment: "[auto:#{website}] #{requested_domain}",
                  auto: true
                }
              end
            end
          end
        end
      end

      p "Обновлено #{routes_to_update.size} routes_to_update"

      return if routes_to_update.blank?

      p routes_to_update

      ApplyRouteChanges.call(routes_to_update)
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

      @follow_dns = {
        cached_at: Time.now,
        websites: websites
      }

      websites
    end
  end
end
