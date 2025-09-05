#!/usr/bin/env ruby

require_relative '../config/application'

class CronTabRunner < BaseClass
  def initialize
    @running = true
    setup_signal_handlers
  end

  def run
    logger.info("Starting KeeneticMaster cron job. PID: #{Process.pid}")
    logger.info("Using database for domain groups management")

    while @running
      begin
        update_cycle
        sleep_with_interruption_check(3600) # 1 hour
      rescue StandardError => e
        handle_error(e, "Cron job execution")
        logger.info("Retrying in 5 minutes due to error...")
        sleep_with_interruption_check(300) # 5 minutes on error
      end
    end

    logger.info("Cron job stopped gracefully")
  end

  private

  def update_cycle
    logger.info("Starting scheduled update of all domain groups")

    result = KeeneticMaster::UpdateAllRoutes.call

    if result&.failure?
      logger.error("Update failed: #{result.failure}")
    else
      logger.info("All domain groups updated successfully")
    end
  end

  def sleep_with_interruption_check(seconds)
    seconds.times do
      return unless @running
      sleep(1)
    end
  end

  def setup_signal_handlers
    %w[INT TERM].each do |signal|
      Signal.trap(signal) do
        logger.info("Received #{signal} signal, shutting down gracefully...")
        @running = false
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  runner = CronTabRunner.new
  puts '>>>>>>>>> crontab ran'
  runner.run
end
