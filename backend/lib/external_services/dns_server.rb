module ExternalServices
  class DnsServer
    SEARCH_PATH = '/api/search'.freeze
    DOMAINS_PATH = '/api/domains'.freeze

    class << self
      def base_url
        ENV['DNS_SERVER_URL']
      end

      def configured?
        base_url.present?
      end

      def search_url
        "#{base_url}#{SEARCH_PATH}"
      end

      def domains_url
        "#{base_url}#{DOMAINS_PATH}"
      end
    end
  end
end
