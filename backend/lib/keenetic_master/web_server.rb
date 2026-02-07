require 'bundler/setup'
Bundler.require :development

require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/cross_origin'
require 'yaml'
require 'json'
require 'uri'
require 'typhoeus'
require 'set'
require_relative '../database'
require_relative '../models'
require_relative 'update_domain_routes'
require_relative 'update_routes_database'
require_relative 'get_group_router_routes'
require_relative 'get_all_routes'
require_relative 'router_routes_manager'
require_relative 'delete_routes'
require_relative 'apply_route_changes'
require_relative 'correct_interface'
require_relative 'configuration'

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

        # Get all routes for this group from router
        router_routes_result = GetAllRoutes.new.call

        if router_routes_result.success?
          router_routes = router_routes_result.value!

          # Filter routes that belong to this group by comment pattern
          comment_pattern = /\[auto:#{Regexp.escape(name)}\]/
          group_routes = router_routes.select do |route|
            comment = route[:comment] || ''
            comment_pattern.match?(comment)
          end

          if group_routes.any?
            logger.info("Deleting #{group_routes.size} routes from router for group '#{name}'")

            routes_to_delete = group_routes.map do |r|
              {
                network: r[:network] || r[:dest],
                mask: r[:mask] || r[:genmask] || '255.255.255.255',
                comment: r[:comment]
              }
            end

            delete_result = DeleteRoutes.call(routes_to_delete)

            if delete_result.success?
              logger.info("Successfully deleted #{group_routes.size} routes from router")
            else
              error_message = delete_result.failure.to_s
              logger.error("Failed to delete routes from router: #{error_message}")
              logger.warn("Proceeding with group deletion despite router deletion failure")
            end
          end
        else
          logger.warn("Could not fetch routes from router, proceeding with group deletion")
        end

        # Delete the group from database
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

        # Get all routes from router once for statistics
        router_routes = []
        router_routes_result = GetAllRoutes.new.call
        if router_routes_result.success?
          router_routes = router_routes_result.value!
        end

        result = domain_groups.map do |group|
          domains_hash = group.to_hash

          # Count routes for this group from router
          comment_pattern = /\[auto:#{Regexp.escape(group.name)}\]/
          group_router_routes = router_routes.select do |route|
            comment = route[:comment] || ''
            comment_pattern.match?(comment)
          end

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
              total_routes: group_router_routes.size,
              synced_routes: group_router_routes.size,
              pending_routes: 0,
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
        interface_changed = false
        if request_body.key?('interfaces')
          interfaces_value = request_body['interfaces']
          interfaces_value = nil if interfaces_value.is_a?(String) && interfaces_value.strip.empty?
          old_interfaces = group.interfaces
          if old_interfaces != interfaces_value
            group.update(interfaces: interfaces_value)
            interface_changed = true
            logger.info("Domain group #{group_id} interface changed from '#{old_interfaces}' to '#{interfaces_value}'")
          end
        end

        # If interface changed, push routes to router to update them with new interface
        push_result = nil
        if interface_changed
          begin
            manager = RouterRoutesManager.new
            push_result = manager.push_group_routes!(group)
            if push_result.success?
              logger.info("Routes updated in router for group '#{group.name}' after interface change")
            else
              logger.warn("Failed to update routes in router: #{push_result.failure}")
            end
          rescue => e
            logger.error("Error pushing routes after interface change: #{e.message}")
          end
        end

        response_data = { success: true, message: "Domain group updated successfully" }
        if interface_changed && push_result
          if push_result.success?
            response_data[:routes_updated] = push_result.value!
          else
            response_data[:routes_warning] = "Interface updated but failed to sync routes: #{push_result.failure}"
          end
        end

        json response_data
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
          # Note: Keenetic uses :host for single IP routes (/32), :network for network routes
          formatted_routes = router_routes.map.with_index do |route, index|
            network_value = route[:network] || route[:host] || route[:dest]
            {
              id: index, # Router routes don't have database IDs
              network: network_value,
              mask: route[:mask] || route[:genmask] || (route[:host] ? '255.255.255.255' : nil),
              interface: route[:interface] || route[:iface],
              gateway: route[:gateway],
              flags: route[:flags],
              table: route[:table],
              dev: route[:dev],
              src: route[:src],
              comment: route[:comment],
              description: "Route to #{network_value} via #{route[:gateway] || 'direct'}"
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

          if params[:group_name] && !params[:group_name].empty?
            group_name = params[:group_name]
            comment_pattern = /\[auto:#{Regexp.escape(group_name)}\]/
            formatted_routes = formatted_routes.select do |route|
              comment = route[:comment] || ''
              comment_pattern.match?(comment)
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

    # API endpoint to push (generate and upload) routes for a specific group to router
    post '/api/domains/:name/push-routes' do
      content_type :json
      begin
        group_name = params[:name]
        group = DomainGroup.find(name: group_name)

        unless group
          status 404
          return json error: "Domain group not found"
        end

        logger.info("Pushing routes for group '#{group_name}' to router")

        manager = RouterRoutesManager.new
        result = manager.push_group_routes!(group)

        if result.success?
          data = result.value!
          logger.info("Successfully pushed routes for group '#{group_name}': added #{data[:added]}, deleted #{data[:deleted]}")
          json({
            success: true,
            message: "Routes pushed successfully for group '#{group_name}'",
            added: data[:added],
            deleted: data[:deleted]
          })
        else
          error_message = result.failure.to_s
          logger.error("Failed to push routes for group '#{group_name}': #{error_message}")
          status 500
          json error: error_message
        end
      rescue => e
        logger.error("Error pushing routes for group '#{params[:name]}': #{e.message}")
        logger.error(e.backtrace.join("\n"))
        status 500
        json(error: e.message, backtrace: e.backtrace)
      end
    end

    # API endpoint to delete all routes for a specific group from router
    delete '/api/router-routes/auto/:group_name' do
      content_type :json
      begin
        group_name = params[:group_name]
        logger.info("Deleting all routes for group '#{group_name}' from router")

        # Get all routes from router
        result = GetAllRoutes.new.call

        unless result.success?
          error_message = result.failure[:error] || "Failed to fetch routes from router"
          logger.error("Error getting router routes: #{error_message}")
          status 500
          return json error: error_message
        end

        router_routes = result.value!

        # Filter routes with comments matching [auto:group_name]
        comment_pattern = /\[auto:#{Regexp.escape(group_name)}\]/
        group_routes = router_routes.select do |route|
          comment = route[:comment] || route[:description]
          comment && comment_pattern.match?(comment.to_s)
        end

        if group_routes.empty?
          logger.info("No routes found for group '#{group_name}'")
          return json({
            success: true,
            message: "No routes found for group '#{group_name}'",
            deleted_count: 0
          })
        end

        logger.info("Found #{group_routes.size} routes for group '#{group_name}' to delete")

        # Prepare routes for deletion
        # Note: Keenetic uses :host for single IP routes (/32), :network for network routes
        # Preserve the original format (host vs network/mask) for accurate deletion
        routes_to_delete = group_routes.map do |route|
          delete_route = {
            comment: route[:comment] || route[:description],
            interface: route[:interface] || route[:iface]
          }

          if route[:host]
            delete_route[:host] = route[:host]
          else
            delete_route[:network] = route[:network] || route[:dest]
            delete_route[:mask] = route[:mask] || route[:genmask] || '255.255.255.255'
          end

          delete_route.compact
        end

        # Delete routes in batches of 10
        batch_size = 10
        total_deleted = 0
        failed_batches = 0
        errors = []

        routes_to_delete.each_slice(batch_size).with_index do |batch, index|
          logger.info("Deleting batch #{index + 1} (#{batch.size} routes)")

          delete_result = DeleteRoutes.call(batch)

          if delete_result.success?
            total_deleted += batch.size
            logger.info("Successfully deleted batch #{index + 1} (#{batch.size} routes)")
          else
            failed_batches += 1
            error_message = delete_result.failure.to_s
            errors << "Batch #{index + 1}: #{error_message}"
            logger.error("Failed to delete batch #{index + 1}: #{error_message}")
          end

          # Small delay between batches to avoid overwhelming the router
          sleep(0.1) if index < (routes_to_delete.size / batch_size.to_f).ceil - 1
        end

        if failed_batches == 0
          logger.info("Successfully deleted all #{total_deleted} routes for group '#{group_name}'")
          json({
            success: true,
            message: "Successfully deleted #{total_deleted} routes for group '#{group_name}'",
            deleted_count: total_deleted
          })
        elsif total_deleted > 0
          logger.warn("Partially deleted routes for group '#{group_name}': #{total_deleted} succeeded, #{failed_batches} batches failed")
          json({
            success: true,
            message: "Deleted #{total_deleted} routes for group '#{group_name}' (#{failed_batches} batches failed)",
            deleted_count: total_deleted,
            failed_batches: failed_batches,
            errors: errors
          })
        else
          error_message = errors.join('; ')
          logger.error("Failed to delete all routes for group '#{group_name}': #{error_message}")
          status 500
          json error: "Failed to delete routes: #{error_message}"
        end
      rescue => e
        logger.error("Error deleting routes for group '#{params[:group_name]}': #{e.message}")
        logger.error(e.backtrace.join("\n"))
        status 500
        json error: e.message
      end
    end

    # API endpoint to delete all routes with [auto prefix
    delete '/api/router-routes/auto' do
      content_type :json
      begin
        logger.info("Deleting all routes with [auto prefix from router")

        # Get all routes from router
        result = GetAllRoutes.new.call

        unless result.success?
          error_message = result.failure[:error] || "Failed to fetch routes from router"
          logger.error("Error getting router routes: #{error_message}")
          status 500
          return json error: error_message
        end

        router_routes = result.value!

        # Filter routes with comments starting with [auto
        auto_routes = router_routes.select do |route|
          comment = route[:comment] || route[:description]
          comment && comment.to_s.start_with?('[auto')
        end

        if auto_routes.empty?
          logger.info("No routes with [auto prefix found")
          return json({
            success: true,
            message: "No routes with [auto prefix found",
            deleted_count: 0
          })
        end

        logger.info("Found #{auto_routes.size} routes with [auto prefix to delete")

        # Prepare routes for deletion
        # Note: Keenetic uses :host for single IP routes (/32), :network for network routes
        # Preserve the original format (host vs network/mask) for accurate deletion
        routes_to_delete = auto_routes.map do |route|
          delete_route = {
            comment: route[:comment] || route[:description],
            interface: route[:interface] || route[:iface]
          }

          if route[:host]
            delete_route[:host] = route[:host]
          else
            delete_route[:network] = route[:network] || route[:dest]
            delete_route[:mask] = route[:mask] || route[:genmask] || '255.255.255.255'
          end

          delete_route.compact
        end

        # Delete routes in batches of 10
        batch_size = 10
        total_deleted = 0
        failed_batches = 0
        errors = []

        routes_to_delete.each_slice(batch_size).with_index do |batch, index|
          logger.info("Deleting batch #{index + 1} (#{batch.size} routes)")

          delete_result = DeleteRoutes.call(batch)

          if delete_result.success?
            total_deleted += batch.size
            logger.info("Successfully deleted batch #{index + 1} (#{batch.size} routes)")
          else
            failed_batches += 1
            error_message = delete_result.failure.to_s
            errors << "Batch #{index + 1}: #{error_message}"
            logger.error("Failed to delete batch #{index + 1}: #{error_message}")
            # Continue with next batch even if this one failed
          end

          # Small delay between batches to avoid overwhelming the router
          sleep(0.1) if index < (routes_to_delete.size / batch_size.to_f).ceil - 1
        end

        if failed_batches == 0
          logger.info("Successfully deleted all #{total_deleted} routes with [auto prefix")
          json({
            success: true,
            message: "Successfully deleted #{total_deleted} routes with [auto prefix",
            deleted_count: total_deleted
          })
        elsif total_deleted > 0
          logger.warn("Partially deleted routes: #{total_deleted} succeeded, #{failed_batches} batches failed")
          json({
            success: true,
            message: "Deleted #{total_deleted} routes with [auto prefix (#{failed_batches} batches failed)",
            deleted_count: total_deleted,
            failed_batches: failed_batches,
            errors: errors
          })
        else
          error_message = errors.join('; ')
          logger.error("Failed to delete all routes: #{error_message}")
          status 500
          json error: "Failed to delete routes: #{error_message}"
        end
      rescue => e
        logger.error("Error deleting routes with [auto prefix: #{e.message}")
        logger.error(e.backtrace.join("\n"))
        status 500
        json error: e.message
      end
    end


    # API endpoint to get router interfaces
    get '/api/router-interfaces' do
      content_type :json
      begin
        unless KeeneticMaster::Configuration.configured?
          return json({
            success: false,
            interfaces: [],
            message: "Router not configured. Please configure settings first."
          })
        end

        logger.info("Getting router interfaces")
        result = KeeneticMaster.interface

        if result.success?
          interfaces_data = result.value!

          # Extract interface IDs and descriptions
          # interfaces_data is a hash where keys are interface IDs
          interfaces = interfaces_data.map do |interface|
            {
              id: interface[:id],
              description: interface[:description],
              name: interface[:description]
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
      rescue KeeneticMaster::Configuration::NotConfiguredError => e
        json({
          success: false,
          interfaces: [],
          message: e.message
        })
      rescue => e
        logger.error("Error getting router interfaces: #{e.message}")
        logger.error(e.backtrace.join("\n"))

        status 500
        json(error: e.message, backtrace: e.backtrace)
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

    # API endpoint to dump database
    get '/api/dumps/database' do
      content_type :json
      begin
        dump_data = {
          version: '2.0',
          timestamp: Time.now.iso8601,
          domain_groups: []
        }

        DomainGroup.order(:name).all.each do |group|
          group_data = {
            id: group.id,
            name: group.name,
            mask: group.mask,
            interfaces: group.interfaces,
            created_at: group.created_at&.iso8601,
            updated_at: group.updated_at&.iso8601,
            domains: []
          }

          group.domains.each do |domain|
            group_data[:domains] << {
              id: domain.id,
              domain: domain.domain,
              type: domain.type,
              created_at: domain.created_at&.iso8601
            }
          end

          dump_data[:domain_groups] << group_data
        end

        json dump_data
      rescue => e
        logger.error("Error dumping database: #{e.message}")
        logger.error(e.backtrace.join("\n"))
        status 500
        json error: e.message
      end
    end

    # API endpoint to import database dump
    post '/api/dumps/database/import' do
      content_type :json
      begin
        request_body = JSON.parse(request.body.read)

        unless request_body.is_a?(Hash) && request_body['domain_groups']
          status 400
          return json error: "Invalid dump format"
        end

        imported_groups = 0
        imported_domains = 0

        Database.connection.transaction do
          # Clear existing data if requested
          if params[:clear] == 'true'
            Domain.dataset.delete
            DomainGroup.dataset.delete
            logger.info("Cleared existing database data")
          end

          # Import domain groups
          request_body['domain_groups'].each do |group_data|
            group = DomainGroup.find(name: group_data['name'])

            if group
              group.update(
                mask: group_data['mask'],
                interfaces: group_data['interfaces']
              )
            else
              group = DomainGroup.create(
                name: group_data['name'],
                mask: group_data['mask'],
                interfaces: group_data['interfaces']
              )
            end

            imported_groups += 1

            # Import domains
            if group_data['domains']
              group_data['domains'].each do |domain_data|
                existing = group.domains_dataset.where(
                  domain: domain_data['domain'],
                  type: domain_data['type'] || 'follow_dns'
                ).first

                unless existing
                  Domain.create(
                    group_id: group.id,
                    domain: domain_data['domain'],
                    type: domain_data['type'] || 'follow_dns'
                  )
                  imported_domains += 1
                end
              end
            end
          end
        end

        logger.info("Database import completed: #{imported_groups} groups, #{imported_domains} domains")
        json({
          success: true,
          message: "Database imported successfully",
          imported: {
            groups: imported_groups,
            domains: imported_domains
          }
        })
      rescue JSON::ParserError
        status 400
        json error: "Invalid JSON format"
      rescue => e
        logger.error("Error importing database: #{e.message}")
        logger.error(e.backtrace.join("\n"))
        status 500
        json error: e.message
      end
    end

    # API endpoint to dump router routes
    get '/api/dumps/router-routes' do
      content_type :json
      begin
        logger.info("Dumping router routes")
        result = GetAllRoutes.new.call

        if result.success?
          router_routes = result.value!

          dump_data = {
            version: '1.0',
            timestamp: Time.now.iso8601,
            routes: router_routes.map do |route|
              {
                network: route[:network] || route[:dest],
                mask: route[:mask] || route[:genmask],
                interface: route[:interface] || route[:iface],
                gateway: route[:gateway],
                flags: route[:flags],
                table: route[:table],
                dev: route[:dev],
                src: route[:src]
              }.compact
            end
          }

          json dump_data
        else
          # Handle different failure structures
          failure = result.failure
          error_message = if failure.is_a?(Hash)
            # GetAllRoutes returns Failure(error: error_msg), so check error first
            if failure[:error]
              # If error is an exception object, get its message
              if failure[:error].respond_to?(:message)
                failure[:error].message
              else
                failure[:error].to_s
              end
            # Check for message (from handle_error in nested failures)
            elsif failure[:message]
              failure[:message]
            # Check for nested request_failure
            elsif failure[:request_failure]
              nested_failure = failure[:request_failure]
              # If nested_failure is a Failure object, extract its error
              if nested_failure.respond_to?(:failure?) && nested_failure.failure?
                nested_failure_hash = nested_failure.failure
                nested_failure_hash[:error] || nested_failure_hash[:message] || "Router request failed"
              # If it's a Typhoeus response
              elsif nested_failure.respond_to?(:code) && nested_failure.respond_to?(:body)
                "Router request failed with code #{nested_failure.code}: #{nested_failure.body&.slice(0, 200)}"
              elsif nested_failure.respond_to?(:message)
                nested_failure.message
              else
                "Router request failed: #{nested_failure.inspect}"
              end
            else
              failure.to_s
            end
          else
            failure.to_s
          end

          error_message = "Failed to fetch routes from router" if error_message.nil? || error_message.empty?

          logger.error("Error dumping router routes: #{error_message}")
          logger.error("Failure details: #{failure.inspect}")

          status 500
          json error: error_message
        end
      rescue => e
        logger.error("Error dumping router routes: #{e.message}")
        logger.error(e.backtrace.join("\n"))

        status 500
        json error: e.message
      end
    end

    # API endpoint to import router routes dump
    post '/api/dumps/router-routes/import' do
      content_type :json
      begin
        request_body = JSON.parse(request.body.read)

        unless request_body.is_a?(Hash) && request_body['routes']
          status 400
          return json error: "Invalid dump format"
        end

        routes_to_add = request_body['routes'].map do |route_data|
          {
            network: route_data['network'] || route_data[:network],
            mask: route_data['mask'] || route_data[:mask],
            interface: route_data['interface'] || route_data[:interface],
            comment: route_data['comment'] || route_data[:comment] || "Imported route"
          }.compact
        end

        if routes_to_add.empty?
          status 400
          return json error: "No routes to import"
        end

        logger.info("Importing #{routes_to_add.size} routes to router")
        result = ApplyRouteChanges.call(routes_to_add)

        if result.success?
          logger.info("Successfully imported #{routes_to_add.size} routes to router")
          json({
            success: true,
            message: "Router routes imported successfully",
            imported: routes_to_add.size
          })
        else
          error_message = result.failure.to_s
          logger.error("Failed to import router routes: #{error_message}")

          status 500
          json error: error_message
        end
      rescue JSON::ParserError
        status 400
        json error: "Invalid JSON format"
      rescue => e
        logger.error("Error importing router routes: #{e.message}")
        logger.error(e.backtrace.join("\n"))
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
          dns_logs: '/api/dns-logs',
          dns_logs_stats: '/api/dns-logs/stats',
          dumps_database: '/api/dumps/database',
          dumps_router_routes: '/api/dumps/router-routes',
          settings: '/api/settings',
          health: '/health'
        },
        timestamp: Time.now.iso8601
      })
    end

    # Health check endpoint
    get '/health' do
      configured = KeeneticMaster::Configuration.configured?
      json({
        status: 'ok',
        configured: configured,
        timestamp: Time.now.iso8601
      })
    end

    # API endpoint to get all settings
    get '/api/settings' do
      content_type :json
      begin
        settings = Setting.get_all_keenetic_settings

        json({
          success: true,
          settings: settings
        })
      rescue => e
        logger.error("Error getting settings: #{e.message}")
        status 500
        json error: e.message
      end
    end

    # API endpoint to update settings
    put '/api/settings' do
      content_type :json
      begin
        request_body = JSON.parse(request.body.read)

        unless request_body.is_a?(Hash)
          status 400
          return json error: "Invalid settings format"
        end

        updated_settings = []

        Database.connection.transaction do
          request_body.each do |key, value|
            next unless Setting::KEENETIC_SETTINGS.include?(key)

            Setting.set(key, value, description: Setting::SETTING_DESCRIPTIONS[key])
            updated_settings << key
          end
        end

        # Reconfigure Keenetic client with new settings
        begin
          KeeneticMaster::Configuration.reconfigure_keenetic_client!
          logger.info("Keenetic client reconfigured with new settings")
        rescue => e
          logger.warn("Could not reconfigure Keenetic client: #{e.message}")
        end

        logger.info("Settings updated: #{updated_settings.join(', ')}")
        json({
          success: true,
          message: "Settings updated successfully",
          updated: updated_settings
        })
      rescue JSON::ParserError
        status 400
        json error: "Invalid JSON format"
      rescue => e
        logger.error("Error updating settings: #{e.message}")
        status 500
        json error: e.message
      end
    end

    # API endpoint to test router connection with current settings
    post '/api/settings/test-connection' do
      content_type :json
      begin
        unless KeeneticMaster::Configuration.configured?
          missing = KeeneticMaster::Configuration.missing_settings
          status 400
          return json({
            success: false,
            message: "Router not configured. Missing settings: #{missing.join(', ')}"
          })
        end

        # Reconfigure client with current settings before testing
        KeeneticMaster::Configuration.reconfigure_keenetic_client!
        
        # Try to connect to router with current settings
        result = KeeneticMaster.interface

        if result.success?
          interfaces_data = result.value!
          interface_count = interfaces_data.size

          json({
            success: true,
            message: "Successfully connected to router",
            interface_count: interface_count
          })
        else
          error_message = result.failure[:message] || "Connection failed"
          status 400
          json({
            success: false,
            message: error_message
          })
        end
      rescue KeeneticMaster::Configuration::NotConfiguredError => e
        status 400
        json({
          success: false,
          message: e.message
        })
      rescue => e
        logger.error("Error testing connection: #{e.message}")
        status 500
        json({
          success: false,
          message: e.message
        })
      end
    end

    # Start the server
    def self.start!
      logger = BaseClass.new.send(:logger)
      logger.info("Starting KeeneticMaster Web UI on #{bind}:#{port}")
      run!
    end
  end
end
