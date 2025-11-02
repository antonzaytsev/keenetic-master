require 'bundler/setup'
Bundler.require :development

require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/cross_origin'
require 'yaml'
require 'json'
require_relative '../database'
require_relative '../models'
require_relative 'update_domain_routes'
require_relative 'update_routes_database'
require_relative 'get_group_router_routes'
require_relative 'get_all_routes'
require_relative 'database_router_sync'
require_relative 'delete_routes'

class KeeneticMaster
  class WebServer < Sinatra::Base
    configure do
      set :port, '3000'
      set :bind, '0.0.0.0'
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
      response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
      response.headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token'
      response.headers['Access-Control-Allow-Origin'] = '*'
      200
    end

    before do
      response.headers['Access-Control-Allow-Origin'] = '*'
      response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
      response.headers['Access-Control-Allow-Headers'] = 'Authorization, Content-Type, Accept, X-User-Email, X-Auth-Token'
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

        # Get all routes for this group that are synced to the router
        synced_routes = Route.where(group_id: group.id, synced_to_router: true).all

        # Delete routes from router if any exist
        if synced_routes.any?
          logger.info("Deleting #{synced_routes.size} routes from router for group '#{name}'")

          routes_to_delete = synced_routes.map { |r| { network: r.network, mask: r.mask, comment: r.comment } }
          delete_result = DeleteRoutes.call(routes_to_delete)

          if delete_result.success?
            logger.info("Successfully deleted #{synced_routes.size} routes from router")

            # Log successful deletion for each route
            synced_routes.each do |route|
              SyncLog.log_success("delete", "route", route.id)
            end
          else
            error_message = delete_result.failure.to_s
            logger.error("Failed to delete routes from router: #{error_message}")

            # Log errors for each route
            synced_routes.each do |route|
              SyncLog.log_error("delete", "route", error_message, route.id)
            end

            # Still proceed with group deletion even if router deletion fails
            # This allows cleanup of database even if router is unreachable
            logger.warn("Proceeding with group deletion despite router deletion failure")
          end
        end

        # Delete the group (this will cascade delete routes from database)
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

    # API endpoint to generate IP addresses for a domain group
    post '/api/domains/:name/generate-ips' do
      content_type :json
      begin
        group_name = params[:name]
        group = DomainGroup.find(name: group_name)

        unless group
          status 404
          return json error: "Domain group not found"
        end

        logger.info("Starting IP generation and database storage for group: #{group_name}")

        # Count routes before generation
        routes_before = Route.where(group_id: group.id).count

        # Use DatabaseRouterSync to generate and store routes in database
        db_sync = DatabaseRouterSync.new
        generated_count = db_sync.send(:generate_routes_for_group, group)

        # Count routes after generation
        routes_after = Route.where(group_id: group.id).count
        routes_added = routes_after - routes_before

        # Now sync the new routes to router if there are any pending
        sync_result = db_sync.sync_to_router!
        synced_count = 0

        if sync_result.success? && sync_result.value!.key?(:synced)
          synced_count = sync_result.value![:synced]
        end

        message = "Successfully generated and stored #{generated_count} routes for group '#{group_name}'. Synced #{synced_count} routes to router."

        # Log the operation
        SyncLog.log_success('generate_ips', 'domain_group', group.id)

        json({
          success: true,
          message: message,
          statistics: {
            added: routes_added,
            deleted: 0, # DatabaseRouterSync doesn't delete during generation
            total: routes_after,
            synced_to_router: synced_count
          }
        })
      rescue => e
        logger.error("Error generating IPs for group '#{params[:name]}': #{e.message}")
        logger.error(e.backtrace.join("\n"))

        # Log the error if we have a group
        if defined?(group) && group
          SyncLog.log_error('generate_ips', 'domain_group', e.message, group.id)
        end

        status 500
        json error: e.message
      end
    end

    # API endpoint to sync routes to router for a domain group
    post '/api/domains/:name/sync-router' do
      content_type :json
      begin
        group_name = params[:name]
        group = DomainGroup.find(name: group_name)

        unless group
          status 404
          return json error: "Domain group not found"
        end

        logger.info("Starting router sync for group: #{group_name}")

        # Get routes that need to be synced for this group
        pending_routes = Route.where(group_id: group.id, synced_to_router: false)

        if pending_routes.empty?
          json({
            success: true,
            message: "No routes to sync for group '#{group_name}'",
            synced_count: 0
          })
        else
          # Use UpdateRoutesDatabase to sync with router
          result = UpdateRoutesDatabase.new.call

          if result.success?
            # Mark routes as synced
            synced_count = pending_routes.count
            pending_routes.update(synced_to_router: true, synced_at: Time.now)

            # Log the operation
            SyncLog.log_success('sync_router', 'domain_group', group.id)

            json({
              success: true,
              message: "Successfully synced #{synced_count} routes to router for group '#{group_name}'",
              synced_count: synced_count
            })
          else
            error_message = result.failure.is_a?(Hash) ? result.failure.to_s : result.failure.to_s
            SyncLog.log_error('sync_router', 'domain_group', error_message, group.id)

            status 500
            json error: error_message
          end
        end
      rescue => e
        logger.error("Error syncing routes to router for group '#{params[:name]}': #{e.message}")
        logger.error(e.backtrace.join("\n"))

        # Log the error if we have a group
        if defined?(group) && group
          SyncLog.log_error('sync_router', 'domain_group', e.message, group.id)
        end

        status 500
        json error: e.message
      end
    end

    # API endpoint to get router routes for a domain group
    get '/api/domains/:name/router-routes' do
      content_type :json
      begin
        group_name = params[:name]
        group = DomainGroup.find(name: group_name)

        unless group
          status 404
          return json error: "Domain group not found"
        end

        logger.info("Getting router routes for group: #{group_name}")
        result = GetGroupRouterRoutes.new.call(group_name)

        if result.success?
          data = result.value!
          router_routes = data[:routes]

          # Transform router routes to match our expected format
          formatted_routes = router_routes.map do |route|
            {
              network: route[:network] || route[:dest],
              mask: route[:mask] || route[:genmask],
              interface: route[:interface] || route[:iface],
              gateway: route[:gateway],
              flags: route[:flags],
              description: "Route to #{route[:network] || route[:dest]} via #{route[:gateway] || 'direct'}"
            }
          end

          json({
            success: true,
            routes: formatted_routes,
            statistics: {
              total_router_routes: data[:total_router_routes],
              matching_routes: data[:matching_routes]
            }
          })
        else
          error_message = result.failure[:error] || "Unknown error occurred"
          logger.error("Error getting router routes for group '#{group_name}': #{error_message}")

          status 500
          json error: error_message
        end
      rescue => e
        logger.error("Error getting router routes for group '#{params[:name]}': #{e.message}")
        logger.error(e.backtrace.join("\n"))

        status 500
        json error: e.message
      end
    end

    # API endpoint to get all routes from router
    get '/api/router-routes' do
      content_type :json
      begin
        logger.info("Getting all routes from router")
        result = GetAllRoutes.new.call

        if result.success?
          router_routes = result.value!

          # Transform router routes to match our expected format
          formatted_routes = router_routes.map.with_index do |route, index|
            {
              id: index, # Router routes don't have database IDs
              network: route[:network] || route[:dest],
              mask: route[:mask] || route[:genmask],
              interface: route[:interface] || route[:iface],
              gateway: route[:gateway],
              flags: route[:flags],
              table: route[:table],
              dev: route[:dev],
              src: route[:src],
              description: "Route to #{route[:network] || route[:dest]} via #{route[:gateway] || 'direct'}"
            }
          end

          # Apply filters if provided
          if params[:interface] && !params[:interface].empty?
            formatted_routes = formatted_routes.select { |route| route[:interface] == params[:interface] }
          end

          if params[:network] && !params[:network].empty?
            search_term = params[:network].downcase
            formatted_routes = formatted_routes.select do |route|
              route[:network]&.downcase&.include?(search_term)
            end
          end

          json({
            success: true,
            routes: formatted_routes,
            total_count: router_routes.size,
            filtered_count: formatted_routes.size
          })
        else
          error_message = result.failure[:error] || "Failed to fetch routes from router"
          logger.error("Error getting all router routes: #{error_message}")

          status 500
          json error: error_message
        end
      rescue => e
        logger.error("Error getting all router routes: #{e.message}")
        logger.error(e.backtrace.join("\n"))

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

        # Filter by group if provided (accept both group_id and group_name)
        if params[:group_id] && !params[:group_id].empty?
          if params[:group_id].match?(/^\d+$/)
            # It's a numeric ID
            routes = routes.where(group_id: params[:group_id].to_i)
          else
            # It's a group name, find the group first
            group = DomainGroup.find(name: params[:group_id])
            routes = routes.where(group_id: group.id) if group
          end
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

    # API endpoint for DNS processing logs with pagination and filtering
    get '/api/dns-logs' do
      content_type :json
      begin
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 50).to_i
        offset = (page - 1) * per_page

        logs = DnsProcessingLog.order(Sequel.desc(:created_at))

        # Apply filters
        if params[:action] && !params[:action].empty?
          logs = logs.where(action: params[:action])
        end

        if params[:group_name] && !params[:group_name].empty?
          logs = logs.where(group_name: params[:group_name])
        end

        if params[:domain] && !params[:domain].empty?
          search_term = params[:domain].downcase
          logs = logs.where(Sequel.ilike(:domain, "%#{search_term}%"))
        end

        if params[:search] && !params[:search].empty?
          search_term = params[:search].downcase
          logs = logs.where(
            Sequel.ilike(:domain, "%#{search_term}%") |
            Sequel.ilike(:group_name, "%#{search_term}%") |
            Sequel.ilike(:comment, "%#{search_term}%")
          )
        end

        # Date range filtering
        if params[:start_date] && !params[:start_date].empty?
          start_date = Time.parse(params[:start_date])
          logs = logs.where { created_at >= start_date }
        end

        if params[:end_date] && !params[:end_date].empty?
          end_date = Time.parse(params[:end_date])
          logs = logs.where { created_at <= end_date }
        end

        total_count = logs.count
        logs = logs.limit(per_page).offset(offset)

        result = {
          logs: logs.map do |log|
            {
              id: log.id,
              action: log.action,
              domain: log.domain,
              group_name: log.group_name,
              network: log.network,
              mask: log.mask,
              interface: log.interface,
              comment: log.comment,
              ip_addresses: log.ip_addresses_array,
              routes_count: log.routes_count,
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
        logger.error("Error loading DNS processing logs: #{e.message}")
        status 500
        json error: e.message
      end
    end

    # API endpoint for DNS logs statistics
    get '/api/dns-logs/stats' do
      content_type :json
      begin
        stats = {
          total_logs: DnsProcessingLog.count,
          recent_24h: DnsProcessingLog.where { created_at > Time.now - 86400 }.count,
          by_action: DnsProcessingLog.group_and_count(:action).to_hash,
          by_group: DnsProcessingLog.group_and_count(:group_name).to_hash,
          total_routes_processed: DnsProcessingLog.sum(:routes_count) || 0
        }

        # Recent activity
        recent_logs = DnsProcessingLog.order(Sequel.desc(:created_at)).limit(10).map do |log|
          {
            id: log.id,
            action: log.action,
            domain: log.domain,
            group_name: log.group_name,
            routes_count: log.routes_count,
            created_at: log.created_at&.iso8601
          }
        end

        result = {
          statistics: stats,
          recent_activity: recent_logs
        }

        json result
      rescue => e
        logger.error("Error loading DNS logs statistics: #{e.message}")
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
          dns_logs: '/api/dns-logs',
          dns_logs_stats: '/api/dns-logs/stats',
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
