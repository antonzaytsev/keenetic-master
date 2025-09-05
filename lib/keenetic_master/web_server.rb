require 'bundler/setup'
Bundler.require :development

require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/cross_origin'
require 'yaml'
require 'json'
require_relative '../database'
require_relative '../models'

class KeeneticMaster
  class WebServer < Sinatra::Base
    configure do
      set :port, ENV.fetch('WEB_PORT', 4567)
      set :bind, ENV.fetch('WEB_BIND', '0.0.0.0')
      set :show_exceptions, true
      set :raise_errors, false

      # Enable CORS for frontend
      register Sinatra::CrossOrigin
      enable :cross_origin
      
      # Database is initialized when models are loaded
    end

    # CORS preflight requests
    options '*' do
      response.headers['Allow'] = 'GET, POST, PUT, DELETE, OPTIONS'
      response.headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token'
      response.headers['Access-Control-Allow-Origin'] = '*'
      200
    end

    before do
      response.headers['Access-Control-Allow-Origin'] = '*'
      content_type :json if request.path_info.start_with?('/api')
    end

    helpers do
      # Legacy method - no longer used since we use database
      def domains_file_path
        Configuration.domains_file
      end

      def load_domains
        domains = {}
        DomainGroup.all.each do |group|
          domains[group.name] = group.to_hash
        end
        domains
      rescue => e
        logger.error("Error loading domains from database: #{e.message}")
        {}
      end

      def save_domain_group(name, data)
        Database.connection.transaction do
          # Delete existing group if it exists
          existing_group = DomainGroup.find(name: name)
          existing_group.destroy if existing_group

          # Create new group from data
          DomainGroup.from_hash(name, data)
        end
        logger.info("Domain group '#{name}' saved successfully to database")
      rescue => e
        logger.error("Error saving domain group '#{name}': #{e.message}")
        raise e
      end

      def delete_domain_group(name)
        group = DomainGroup.find(name: name)
        return false unless group

        group.destroy
        logger.info("Domain group '#{name}' deleted successfully from database")
        true
      rescue => e
        logger.error("Error deleting domain group '#{name}': #{e.message}")
        raise e
      end

      def logger
        @logger ||= BaseClass.new.send(:logger)
      end
    end

    # API endpoint to get domain groups with statistics
    get '/api/domain-groups' do
      begin
        domain_groups = DomainGroup.order(:name).all
        
        result = domain_groups.map do |group|
          domains_hash = group.to_hash
          
          {
            id: group.id,
            name: group.name,
            mask: group.mask,
            interfaces: group.interfaces,
            domains: domains_hash,
            statistics: {
              total_domains: group.domains_dataset.count,
              regular_domains: group.domains_dataset.where(type: 'regular').count,
              follow_dns_domains: group.domains_dataset.where(type: 'follow_dns').count,
              total_routes: group.routes_dataset.count,
              synced_routes: group.routes_dataset.where(synced_to_router: true).count,
              pending_routes: group.routes_dataset.where(synced_to_router: false).count,
              last_updated: group.updated_at&.iso8601
            },
            created_at: group.created_at&.iso8601,
            updated_at: group.updated_at&.iso8601
          }
        end
        
        json result
      rescue => e
        logger.error("Error loading domain groups: #{e.message}")
        status 500
        json error: e.message
      end
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
        group = DomainGroup.find(name: params[:name])
        if group
          json group.to_hash
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

        # Validate the input
        unless request_body.is_a?(Hash) || request_body.is_a?(Array)
          status 400
          return json error: "Invalid domain data format"
        end

        save_domain_group(params[:name], request_body)

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
        if delete_domain_group(params[:name])
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


    # API endpoint for IP addresses with filtering
    get '/api/ip-addresses' do
      content_type :json
      begin
        routes = Route.order(:network, :mask)
        
        # Filter by sync status if provided
        if params[:sync_status]
          case params[:sync_status]
          when 'synced'
            routes = routes.where(synced_to_router: true)
          when 'unsynced'
            routes = routes.where(synced_to_router: false)
          end
        end
        
        # Filter by group if provided
        if params[:group_id] && !params[:group_id].empty?
          routes = routes.where(group_id: params[:group_id])
        end
        
        result = routes.map do |route|
          {
            id: route.id,
            network: route.network,
            mask: route.mask,
            interface: route.interface,
            comment: route.comment,
            group_name: route.domain_group&.name,
            synced_to_router: route.synced_to_router,
            synced_at: route.synced_at&.iso8601,
            created_at: route.created_at&.iso8601,
            updated_at: route.updated_at&.iso8601
          }
        end
        
        json result
      rescue => e
        status 500
        json error: e.message
      end
    end

    # API endpoint for sync statistics
    get '/api/sync-stats' do
      begin
        recent_logs = SyncLog.order(Sequel.desc(:created_at)).limit(100)
        recent_failures = SyncLog.recent_failures(24)
        
        stats = {
          total_routes: Route.count,
          synced_routes: Route.where(synced_to_router: true).count,
          pending_sync: Route.pending_sync.count,
          stale_routes: Route.stale(60).count
        }
        
        result = {
          statistics: stats,
          recent_logs: recent_logs.map do |log|
            {
              id: log.id,
              operation: log.operation,
              resource_type: log.resource_type,
              resource_id: log.resource_id,
              success: log.success,
              error_message: log.error_message,
              created_at: log.created_at&.iso8601
            }
          end,
          recent_failures: recent_failures.map do |log|
            {
              id: log.id,
              operation: log.operation,
              resource_type: log.resource_type,
              resource_id: log.resource_id,
              error_message: log.error_message,
              created_at: log.created_at&.iso8601
            }
          end
        }
        
        json result
      rescue => e
        logger.error("Error loading sync statistics: #{e.message}")
        status 500
        json error: e.message
      end
    end

    # API endpoint for sync logs with pagination
    get '/api/sync-logs' do
      content_type :json
      begin
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 50).to_i
        offset = (page - 1) * per_page
        
        logs = SyncLog.order(Sequel.desc(:created_at)).limit(per_page).offset(offset)
        total_count = SyncLog.count
        
        result = {
          logs: logs.map do |log|
            {
              id: log.id,
              operation: log.operation,
              resource_type: log.resource_type,
              resource_id: log.resource_id,
              success: log.success,
              error_message: log.error_message,
              created_at: log.created_at&.iso8601
            }
          end,
          pagination: {
            page: page,
            per_page: per_page,
            total_count: total_count,
            total_pages: (total_count.to_f / per_page).ceil
          }
        }
        
        json result
      rescue => e
        status 500
        json error: e.message
      end
    end

    # Root endpoint - API info
    get '/' do
      json({
        name: 'KeeneticMaster API',
        version: '1.0.0',
        status: 'ok',
        endpoints: {
          domain_groups: '/api/domain-groups',
          domains: '/api/domains',
          ip_addresses: '/api/ip-addresses',
          sync_stats: '/api/sync-stats',
          sync_logs: '/api/sync-logs',
          health: '/health'
        },
        timestamp: Time.now.iso8601
      })
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
