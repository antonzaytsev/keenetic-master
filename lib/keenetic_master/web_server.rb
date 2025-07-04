require 'sinatra/base'
require 'sinatra/json'
require 'yaml'
require 'json'

class KeeneticMaster
  class WebServer < Sinatra::Base
    configure do
      set :port, ENV.fetch('WEB_PORT', 4567)
      set :bind, ENV.fetch('WEB_BIND', '0.0.0.0')
      set :public_folder, File.join(File.dirname(__FILE__), '..', '..', 'public')
      set :views, File.join(File.dirname(__FILE__), '..', '..', 'views')
      set :show_exceptions, true
      set :raise_errors, false
    end

    helpers do
      def domains_file_path
        Configuration.domains_file
      end

      def load_domains
        return {} unless File.exist?(domains_file_path)
        YAML.load_file(domains_file_path) || {}
      rescue => e
        logger.error("Error loading domains file: #{e.message}")
        {}
      end

      def save_domains(domains)
        File.write(domains_file_path, domains.to_yaml)
        logger.info("Domains file updated successfully")
      rescue => e
        logger.error("Error saving domains file: #{e.message}")
        raise e
      end

      def logger
        @logger ||= BaseClass.new.send(:logger)
      end
    end

    # Main page - shows all domain groups
    get '/' do
      @domains = load_domains
      erb :index
    end

    # API endpoint to get all domains
    get '/api/domains' do
      content_type :json
      begin
        domains = load_domains
        json domains
      rescue => e
        status 500
        json error: e.message
      end
    end

    # API endpoint to get specific domain group
    get '/api/domains/:name' do
      content_type :json
      begin
        domains = load_domains
        domain = domains[params[:name]]
        if domain
          json domain
        else
          status 404
          json error: "Domain group not found"
        end
      rescue => e
        status 500
        json error: e.message
      end
    end

    # API endpoint to create or update domain group
    post '/api/domains/:name' do
      content_type :json
      begin
        request_body = JSON.parse(request.body.read)
        domains = load_domains
        
        # Validate the input
        unless request_body.is_a?(Hash) || request_body.is_a?(Array)
          status 400
          return json error: "Invalid domain data format"
        end
        
        domains[params[:name]] = request_body
        save_domains(domains)
        
        json success: true, message: "Domain group '#{params[:name]}' updated successfully"
      rescue JSON::ParserError
        status 400
        json error: "Invalid JSON format"
      rescue => e
        status 500
        json error: e.message
      end
    end

    # API endpoint to delete domain group
    delete '/api/domains/:name' do
      content_type :json
      begin
        domains = load_domains
        if domains.key?(params[:name])
          domains.delete(params[:name])
          save_domains(domains)
          json success: true, message: "Domain group '#{params[:name]}' deleted successfully"
        else
          status 404
          json error: "Domain group not found"
        end
      rescue => e
        status 500
        json error: e.message
      end
    end

    # Form page for editing specific domain group
    get '/edit/:name' do
      @group_name = params[:name]
      @domains = load_domains
      @domain_data = @domains[@group_name] || []
      erb :edit
    end

    # Form page for creating new domain group
    get '/new' do
      @group_name = ""
      @domain_data = []
      erb :edit
    end

    # Health check endpoint
    get '/health' do
      json status: 'ok', timestamp: Time.now.iso8601
    end

    # Start the server
    def self.start!
      logger = BaseClass.new.send(:logger)
      logger.info("Starting KeeneticMaster Web UI on #{bind}:#{port}")
      run!
    end
  end
end 