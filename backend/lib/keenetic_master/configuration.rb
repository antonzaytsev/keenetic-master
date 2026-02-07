require 'keenetic'

class KeeneticMaster
  module Configuration
    class ConfigurationError < StandardError; end

    class << self
      def configure_keenetic_client!
        Keenetic.configure do |config|
          config.host = get_setting('keenetic_host')
          config.login = get_setting('keenetic_login')
          config.password = get_setting('keenetic_password')
          config.timeout = 30
          config.logger = Logger.new($stdout) if ENV['DEBUG']
        end
      end

      def reconfigure_keenetic_client!
        @keenetic_client = nil
        configure_keenetic_client!
        @keenetic_client = Keenetic.client
      end

      def keenetic_client
        @keenetic_client ||= begin
          configure_keenetic_client!
          Keenetic.client
        end
      end

      def vpn_interface
        get_setting('keenetic_vpn_interface', default: 'Wireguard0')
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

      def request_dumps_dir
        ENV.fetch('REQUEST_DUMPS_DIR', 'tmp/request-dumps')
      end

      def validate!
        configure_keenetic_client!
        
        # DOMAINS_FILE is now optional since we use database
        # Only validate it exists if it's explicitly set for migration purposes
        if ENV['DOMAINS_FILE'] && !File.exist?(domains_file)
          raise ConfigurationError, "Domains file not found: #{domains_file}"
        end

        FileUtils.mkdir_p(request_dumps_dir) unless File.directory?(request_dumps_dir)
      end

      private

      def get_setting(key, default: nil, required: true)
        db_value = nil
        begin
          db_value = Setting.get(key) if defined?(Setting)
        rescue => e
          # Database might not be available yet during initial setup
        end
        
        return db_value if db_value.present?
        return default if default.present?
        
        if required
          raise ConfigurationError, "Required setting '#{key}' is not configured. Set it via the Settings page."
        end
        
        nil
      end
    end
  end
end