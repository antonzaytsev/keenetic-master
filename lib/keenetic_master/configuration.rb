class KeeneticMaster
  module Configuration
    class ConfigurationError < StandardError; end

    class << self
      def keenetic_credentials
        @keenetic_credentials ||= {
          login: required_env('KEENETIC_LOGIN'),
          password: required_env('KEENETIC_PASSWORD'),
          host: required_env('KEENETIC_HOST')
        }
      end

      def vpn_interfaces
        interfaces = ENV['KEENETIC_VPN_INTERFACE'] || ENV['KEENETIC_VPN_INTERFACES'] || 'Wireguard0'
        interfaces.split(',').map(&:strip)
      end

      def domains_file
        ENV['DOMAINS_FILE'] || 'config/domains.yml'
      end

      def dns_servers
        (ENV['DNS_SERVERS'] || '1.1.1.1,8.8.8.8').split(',').map(&:strip)
      end

      def domains_mask
        ENV.fetch('DOMAINS_MASK', '32')
      end

      def minimize_mode?
        ENV.fetch('MINIMIZE', 'false').downcase == 'true'
      end

      def delete_missing_routes?
        ENV.fetch('DELETE_ROUTES', 'true').downcase == 'true'
      end

      def cookie_file_path
        ENV.fetch('COOKIE_FILE', 'config/cookie')
      end

      def request_dumps_dir
        ENV.fetch('REQUEST_DUMPS_DIR', 'tmp/request-dumps')
      end

      def validate!
        required_env('KEENETIC_LOGIN')
        required_env('KEENETIC_PASSWORD')
        required_env('KEENETIC_HOST')
        
        # DOMAINS_FILE is now optional since we use database
        # Only validate it exists if it's explicitly set for migration purposes
        if ENV['DOMAINS_FILE'] && !File.exist?(domains_file)
          raise ConfigurationError, "Domains file not found: #{domains_file}"
        end

        FileUtils.mkdir_p(request_dumps_dir) unless File.directory?(request_dumps_dir)
        FileUtils.mkdir_p(File.dirname(cookie_file_path)) unless File.directory?(File.dirname(cookie_file_path))
      end

      private

      def required_env(key)
        ENV.fetch(key) do
          raise ConfigurationError, "Required environment variable #{key} is not set"
        end
      end
    end
  end
end 