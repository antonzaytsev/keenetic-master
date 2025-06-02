require_relative 'mutate_route_request'

class KeeneticMaster
  class FollowDnsLogs < MutateRouteRequest
    WAIT = 1

    def call(dns_file)
      if !File.exist?(dns_file) || !File.readable?(dns_file)
        puts "Не указаны или недоступен файл в переменной окружения DNS_LOGS_PATH `#{dns_file}`"
        return
      end

      if follow_dns.blank?
        puts "Нет ни одной группы в файле #{ENV.fetch('DOMAINS_FILE')} с параметром follow_dns"
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
      # listener.stop
    end

    private

    def process_logs(new_content)
      routes_to_update = []

      new_content.lines.each do |line|
        group = JSON.parse(line)
        next if group['ip_address'].blank?

        follow_dns.each do |website, data|
          data[:domains].each do |domain|
            next if group['domain'] !~ /#{Regexp.escape(domain)}$/

            group[:ip_address].each do |ip_address|
              data[:interfaces].each do |interface|
                routes_to_update << {
                  host: ip_address,
                  interface: CorrectInterface.call(interface),
                  comment: "[auto: #{website}] #{domain}",
                  auto: true
                }
              end
            end
          end
        end
      end

      return if routes_to_update.blank?

      ApplyRouteChanges.call(routes_to_update)
    end

    def follow_dns
      return @follow_dns if defined?(@follow_dns)

      @follow_dns = {}
      YAML.load_file(ENV.fetch('DOMAINS_FILE')).each do |website, data|
        next unless data.is_a?(Hash)
        next if data['follow_dns'].blank?

        @follow_dns[website] = {
          domains: data['follow_dns'],
          interfaces: (data['settings']&.dig('interfaces') || ENV['KEENETIC_VPN_INTERFACES']).split(',').map(&:strip),
        }
      end
      @follow_dns
    end
  end
end
