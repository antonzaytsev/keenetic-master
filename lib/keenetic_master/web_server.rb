require 'bundler/setup'
Bundler.require :development

require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/cross_origin'
require 'yaml'
require 'json'
require 'uri'
require_relative '../database'
require_relative '../models'
require_relative 'update_domain_routes'
require_relative 'update_routes_database'
require_relative 'get_group_router_routes'
require_relative 'get_all_routes'
require_relative 'database_router_sync'
require_relative 'delete_routes'
require_relative 'apply_route_changes'
require_relative 'correct_interface'

class KeeneticMaster
  class WebServer < Sinatra::Base
    configure :development do
      require 'sinatra/reloader'
      register Sinatra::Reloader
      also_reload 'lib/**/*.rb'
      also_reload 'config/**/*.rb'
    end

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
          existing_group = DomainGroup.find(name: name)
          existing_group.destroy if existing_group

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
              total_domains: group.domains_dataset.where(type: 'follow_dns').count,
              regular_domains: 0,
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

    # API endpoint to update group by ID (for renaming and other updates)
    put '/api/domain-groups/:id' do
      content_type :json
      begin
        group_id = params[:id].to_i
        group = DomainGroup[group_id]

        unless group
          status 404
          return json error: "Domain group not found"
        end

        request_body = JSON.parse(request.body.read)

        # Update group name if provided
        if request_body['name'] && request_body['name'] != group.name
          # Check if new name already exists
          existing = DomainGroup.find(name: request_body['name'])
          if existing && existing.id != group_id
            status 400
            return json error: "Domain group with name '#{request_body['name']}' already exists"
          end
          old_name = group.name
          group.update(name: request_body['name'])
          logger.info("Domain group #{group_id} renamed from '#{old_name}' to '#{request_body['name']}'")
        end

        # Update mask if provided
        if request_body.key?('mask')
          mask_value = request_body['mask']
          mask_value = nil if mask_value.is_a?(String) && mask_value.strip.empty?
          group.update(mask: mask_value)
        end

        # Update interfaces if provided
        if request_body.key?('interfaces')
          interfaces_value = request_body['interfaces']
          interfaces_value = nil if interfaces_value.is_a?(String) && interfaces_value.strip.empty?
          group.update(interfaces: interfaces_value)
        end

        json success: true, message: "Domain group updated successfully"
      rescue JSON::ParserError
        status 400
        json error: "Invalid JSON format"
      rescue => e
        logger.error("Error updating domain group: #{e.message}")
        status 500
        json error: e.message
      end
    end

    # API endpoint to get domains for a group with type information
    get '/api/domain-groups/:id/domains' do
      content_type :json
      begin
        group_id = params[:id].to_i
        group = DomainGroup[group_id]

        unless group
          status 404
          return json error: "Domain group not found"
        end

        # Get all DNS monitored domains - explicitly convert to plain hash
        domains_array = []
        group.domains_dataset.where(type: 'follow_dns').order(:domain).each do |domain|
          domains_array << {
            id: domain.id.to_i,
            domain: domain.domain.to_s,
            type: 'follow_dns'
          }
        end

        response_data = {
          group_id: group_id,
          group_name: group.name.to_s,
          domains: domains_array,
          statistics: {
            total: domains_array.length,
            regular: 0,
            follow_dns: domains_array.length
          }
        }

        json response_data
      rescue => e
        logger.error("Error getting domains for group: #{e.message}")
        logger.error(e.backtrace.join("\n"))
        status 500
        json error: e.message
      end
    end

    # API endpoint to add a domain to a group
    post '/api/domain-groups/:id/domains' do
      content_type :json
      begin
        group_id = params[:id].to_i
        request_body = JSON.parse(request.body.read)
        domain_name = request_body['domain']&.strip
        # Type parameter is ignored - all domains are DNS monitored
        domain_type = 'follow_dns'

        unless domain_name && !domain_name.empty?
          status 400
          return json error: "Domain name is required"
        end

        group = DomainGroup[group_id]
        unless group
          status 404
          return json error: "Domain group not found"
        end

        # Check if domain already exists in this group
        existing = group.domains_dataset.where(domain: domain_name, type: domain_type).first
        if existing
          status 400
          return json error: "Domain '#{domain_name}' already exists in this group"
        end

        # Add the domain
        Domain.create(group_id: group_id, domain: domain_name, type: domain_type)
        logger.info("Domain '#{domain_name}' added to group '#{group.name}'")

        json success: true, message: "Domain '#{domain_name}' added successfully"
      rescue JSON::ParserError
        status 400
        json error: "Invalid JSON format"
      rescue => e
        logger.error("Error adding domain: #{e.message}")
        status 500
        json error: e.message
      end
    end

    # API endpoint to delete a domain from a group
    delete '/api/domain-groups/:id/domains/:domain' do
      content_type :json
      begin
        group_id = params[:id].to_i
        domain_name = URI.decode_www_form_component(params[:domain])
        # Type parameter is ignored - all domains are DNS monitored
        domain_type = 'follow_dns'

        group = DomainGroup[group_id]
        unless group
          status 404
          return json error: "Domain group not found"
        end

        domain = group.domains_dataset.where(domain: domain_name, type: domain_type).first
        unless domain
          status 404
          return json error: "Domain '#{domain_name}' not found in group"
        end

        domain.destroy
        logger.info("Domain '#{domain_name}' deleted from group '#{group.name}'")

        json success: true, message: "Domain '#{domain_name}' deleted successfully"
      rescue => e
        logger.error("Error deleting domain: #{e.message}")
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


    # API endpoint to get router interfaces
    get '/api/router-interfaces' do
      content_type :json
      begin
        logger.info("Getting router interfaces")
        result = KeeneticMaster.interface

        if result.success?
          interfaces_data = result.value!
          
          # Extract interface IDs and descriptions
          # interfaces_data is a hash where keys are interface IDs
          interfaces = interfaces_data.map do |id, data|
            {
              id: id.to_s,
              description: (data.is_a?(Hash) ? (data['description'] || data[:description]) : nil) || id.to_s,
              name: (data.is_a?(Hash) ? (data['name'] || data[:name]) : nil) || id.to_s
            }
          end

          # Sort by description/name for better UX
          interfaces.sort_by! { |iface| iface[:description] || iface[:id] }

          json({
            success: true,
            interfaces: interfaces
          })
        else
          error_message = result.failure[:message] || "Failed to fetch interfaces from router"
          logger.error("Error getting router interfaces: #{error_message}")

          status 500
          json error: error_message
        end
      rescue => e
        logger.error("Error getting router interfaces: #{e.message}")
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
