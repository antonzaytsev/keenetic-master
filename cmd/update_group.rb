#!/usr/bin/env ruby

require_relative '../config/application'

class UpdateGroupCommand < BaseClass
  def initialize(argv)
    @argv = argv
  end

  def run
    return show_help if help_requested?

    if @argv.any?
      update_specific_groups(@argv)
    else
      update_all_groups
    end
  end

  private

  def help_requested?
    @argv.include?('-h') || @argv.include?('--help')
  end

  def show_help
    puts <<~HELP
      Usage: #{$PROGRAM_NAME} [OPTIONS] [GROUP_NAMES...]
      
      Update domain routes for Keenetic router.
      
      Arguments:
        GROUP_NAMES    One or more group names to update (if not specified, updates all groups)
      
      Options:
        -h, --help     Show this help message
      
      Environment Variables:
        DELETE_ROUTES  Set to 'false' to prevent deletion of missing routes (default: 'true')
        MINIMIZE       Set to 'true' to use minimize mode (default: 'false')
      
      Examples:
        #{$PROGRAM_NAME}                    # Update all groups
        #{$PROGRAM_NAME} github youtube     # Update specific groups
        DELETE_ROUTES=false #{$PROGRAM_NAME} github  # Update without deleting missing routes
    HELP
  end

  def update_specific_groups(groups)
    logger.info("Starting update for groups: #{groups.join(', ')}")

    begin
      delete_missing = KeeneticMaster::Configuration.delete_missing_routes?

      result = KeeneticMaster::UpdateDomainRoutesMinimize.call(groups, delete_missing: delete_missing)

      if result.success?
        logger.info(result.value![:message])
        puts result.value![:message]
      else
        logger.error("Update failed: #{result.failure[:message]}")
        puts "Error: #{result.failure[:message]}"
        exit(1)
      end

    rescue StandardError => e
      error_result = handle_error(e, "Group update")
      puts "Error: #{error_result.failure[:message]}"
      exit(1)
    end
  end

  def update_all_groups
    logger.info("Starting update for all groups from #{KeeneticMaster::Configuration.domains_file}")

    begin
      result = KeeneticMaster::UpdateAllRoutes.call

      if result&.failure?
        logger.error("Update failed: #{result.failure}")
        puts "Error: Update failed"
        exit(1)
      else
        logger.info("All groups updated successfully")
        puts "All groups updated successfully"
      end

    rescue StandardError => e
      binding.pry
      error_result = handle_error(e, "All groups update")
      puts "Error: #{error_result.failure[:message]}"
      exit(1)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  command = UpdateGroupCommand.new(ARGV)
  command.run
end
