require 'keenetic'

class KeeneticMaster
  module Configuration
    class ConfigurationError < StandardError; end
    class NotConfiguredError < ConfigurationError; end

    REQUIRED_SETTINGS = %w[keenetic_host keenetic_login keenetic_password].freeze

    class << self
      def configure_keenetic_client!
        validate_required_settings!
        
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

      def configured?
        missing_settings.empty?
      end

      def missing_settings
        REQUIRED_SETTINGS.select do |key|
          get_setting(key, required: false).blank?
        end
      end

      def validate_required_settings!
        missing = missing_settings
        if missing.any?
          raise NotConfiguredError, "Router not configured. Missing: #{missing.join(', ')}. Configure via Settings page."
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

      private

      def get_setting(key, default: nil, required: false)
        db_value = nil
        begin
          db_value = Setting.get(key) if defined?(Setting)
        rescue => e
          # Database might not be available yet during initial setup
        end
        
        return db_value if db_value.present?
        return default if default.present?
        
        nil
      end
    end
  end
end