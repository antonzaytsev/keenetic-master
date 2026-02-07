require_relative '../database'
require_relative '../models'
require_relative 'database_router_sync'
require_relative 'apply_route_changes'
require_relative 'delete_routes'
require_relative 'correct_interface'
require 'resolv'

class KeeneticMaster
  class UpdateRoutesDatabase < BaseClass
    def initialize
      super
      @sync_service = DatabaseRouterSync.new
      @logger = logger
    end

    # Update routes for a specific group (sync to Keenetic router)
    def call(group_name)
      @logger.info("Starting route update for group: #{group_name}")
      start_time = Time.now

      group = DomainGroup.find(name: group_name)
      unless group
        return Failure(message: "Domain group '#{group_name}' not found")
      end

      begin
        result = @sync_service.sync_group_to_router!(group)
        
        if result.success?
          data = result.value!
          elapsed_time = (Time.now - start_time).round(2)
          message = "Successfully processed group '#{group_name}'. Added: #{data[:added]}, deleted: #{data[:deleted]}. Time: #{elapsed_time}s"
          
          @logger.info(message)
          
          Success(
            group: group_name,
            added: data[:added],
            deleted: data[:deleted],
            message: message
          )
        else
          Failure(message: result.failure.to_s)
        end
      rescue => e
        @logger.error("Failed to update routes for group '#{group_name}': #{e.message}")
        Failure(message: e.message)
      end
    end

    # Update routes for all groups
    def call_all
      @logger.info("Starting route update for all groups")
      start_time = Time.now

      results = {
        groups_processed: 0,
        total_added: 0,
        total_deleted: 0,
        errors: []
      }

      DomainGroup.all.each do |group|
        begin
          result = call(group.name)
          
          if result.success?
            data = result.value!
            results[:groups_processed] += 1
            results[:total_added] += data[:added]
            results[:total_deleted] += data[:deleted]
          else
            results[:errors] << "#{group.name}: #{result.failure[:message]}"
          end
          
        rescue => e
          @logger.error("Failed to process group '#{group.name}': #{e.message}")
          results[:errors] << "#{group.name}: #{e.message}"
        end
      end

      elapsed_time = (Time.now - start_time).round(2)
      
      if results[:errors].empty?
        message = "Successfully processed all #{results[:groups_processed]} groups. Added: #{results[:total_added]}, deleted: #{results[:total_deleted]}. Time: #{elapsed_time}s"
        @logger.info(message)
        
        Success(results.merge(message: message))
      else
        message = "Processed #{results[:groups_processed]} groups with #{results[:errors].size} errors. Time: #{elapsed_time}s"
        @logger.warn(message)
        @logger.warn("Errors: #{results[:errors].join(', ')}")
        
        Failure(results.merge(message: message))
      end
    end

    # Minimize mode - full sync with cleanup
    def call_minimize(delete_missing: true)
      @logger.info("Starting minimize mode update")
      
      result = @sync_service.full_sync!
      
      if delete_missing && result.success?
        cleanup_result = @sync_service.cleanup_obsolete_routes!
        if cleanup_result.success?
          cleaned_count = cleanup_result.value![:cleaned_up] || 0
          result.value![:cleaned_up] = cleaned_count
        end
      end
      
      result
    end
  end
end
