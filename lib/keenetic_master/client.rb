require 'typhoeus'
require 'json'

class KeeneticMaster
  class Client
    def self.get(url)
      new.get(url)
    end

    def self.post_rci(body)
      new.post_rci(body)
    end

    def get(url)
      ensure_logged_in
      make_request(url)
    end

    def post_rci(body)
      ensure_logged_in
      make_request('rci/', body)
    end

    private

    def ensure_logged_in
      auth_response = make_request('auth')
      return if auth_response.code == 200

      raise "Unknown error on GET /auth: #{auth_response.code}" if auth_response.code != 401

      md5 = Digest::MD5.hexdigest("#{keenetic_credentials.fetch(:login)}:#{auth_response.headers["X-NDM-Realm"]}:#{keenetic_credentials.fetch(:password)}")
      sha = Digest::SHA256.hexdigest("#{auth_response.headers["X-NDM-Challenge"]}#{md5}")

      make_request(
        'auth',
        {
          login: keenetic_credentials.fetch(:login),
          password: sha
        }
      )
    end

    def make_request(path, body = nil)
      url = "http://#{keenetic_credentials.fetch(:host)}/#{path}"

      options = {
        cookiefile: 'config/cookie',
        cookiejar: 'config/cookie',
        method: :get,
        headers: {
          "Content-Type" => "application/json",
          "Accept" => "application/json",
          "Connection" => "keep-alive",
        }
        # verbose: true
      }

      if body
        options.merge!(
          method: :post,
          body: body.to_json
        )
      end

      Typhoeus::Request.new(url, options).run
    end

    def headers
      cookie = File.read('config/cookie').strip
      {
        "Content-Type" => "application/json",
        "Host" => "http://192.168.0.1:80",
        "Accept" => "application/json, text/plain, */*",
        "accept-encoding" => "gzip, deflate",
        "connection" => "keep-alive",
        "cookie" => "sysmode=router; ZLWSOLJNSPVRBK=#{cookie}; IVACNMCTSHSEHJAP=#{cookie}"
      }
    end

    def keenetic_credentials
      @keenetic_credentials ||= {
        login: ENV.fetch('KEENETIC_LOGIN'),
        password: ENV.fetch('KEENETIC_PASSWORD'),
        host: ENV.fetch('KEENETIC_HOST')
      }
    end
  end
end
