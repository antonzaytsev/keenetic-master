require 'digest'
require 'typhoeus'

class KeeneticMaster
  class Client < BaseClass
    class ClientError < StandardError; end
    class AuthenticationError < ClientError; end
    class RequestError < ClientError; end

    def self.get(url)
      new.get(url)
    end

    def self.post_rci(body)
      new.post_rci(body)
    end

    def get(url)
      ensure_logged_in
      make_request(url)
    rescue StandardError => e
      handle_error(e, "GET request to #{url}")
    end

    def post_rci(body)
      ensure_logged_in
      make_request('rci/', body)
    rescue StandardError => e
      handle_error(e, "POST RCI request")
    end

    private

    def ensure_logged_in
      auth_response = make_request('auth')

      # Handle network errors (code 0 or nil means connection failed)
      response_code = auth_response.code rescue nil

      if response_code.nil? || response_code == 0
        return_code = auth_response.return_code rescue nil
        error_msg = case return_code
        when :couldnt_connect
          "Cannot connect to router at #{build_url('auth')}. Check if router is reachable."
        when :operation_timedout
          "Connection to router timed out. Router may be unreachable or slow."
        when :couldnt_resolve_host
          "Cannot resolve router hostname. Check DNS or host configuration."
        when nil
          # return_code might be nil in some cases
          "Network error connecting to router (response code: #{response_code || 'nil'}). Check if router is reachable."
        else
          "Network error connecting to router: #{return_code}"
        end
        raise RequestError, error_msg
      end

      return if response_code == 200

      return authenticate if response_code == 401

      raise RequestError, "Unexpected response from /auth: #{response_code}"
    end

    def authenticate
      auth_response = make_request('auth')

      unless auth_response.headers["X-NDM-Realm"] && auth_response.headers["X-NDM-Challenge"]
        raise AuthenticationError, "Missing authentication headers in response"
      end

      credentials = Configuration.keenetic_credentials

      md5_hash = Digest::MD5.hexdigest(
        "#{credentials[:login]}:#{auth_response.headers["X-NDM-Realm"]}:#{credentials[:password]}"
      )

      sha_hash = Digest::SHA256.hexdigest(
        "#{auth_response.headers["X-NDM-Challenge"]}#{md5_hash}"
      )

      login_response = make_request('auth', {
        login: credentials[:login],
        password: sha_hash
      })

      return if login_response.code == 200

      raise AuthenticationError, "Authentication failed with code: #{login_response.code}"
    end

    def make_request(path, body = nil)
      url = build_url(path)
      options = build_request_options(body)

      logger.debug("Making request to #{url}")

      response = Typhoeus::Request.new(url, options).run

      logger.debug("Response code: #{response.code}")

      response
    end

    def build_url(path)
      host = Configuration.keenetic_credentials[:host]
      "http://#{host}/#{path}"
    end

    def build_request_options(body = nil)
      options = {
        cookiefile: Configuration.cookie_file_path,
        cookiejar: Configuration.cookie_file_path,
        method: body ? :post : :get,
        headers: default_headers,
        timeout: 30,
        connecttimeout: 10
      }

      options[:body] = body.to_json if body
      options
    end

    def default_headers
      {
        "Content-Type" => "application/json",
        "Accept" => "application/json",
        "Connection" => "keep-alive",
        "User-Agent" => "KeeneticMaster/#{KeeneticMaster::VERSION}"
      }
    end
  end
end
