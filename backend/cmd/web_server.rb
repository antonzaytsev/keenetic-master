#!/usr/bin/env ruby

require_relative '../config/application'

# Start the web server
begin
  puts "Starting KeeneticMaster Web UI..."
  puts "Access the web interface at: http://localhost:#{ENV.fetch('WEB_PORT', 4567)}"
  puts "Press Ctrl+C to stop"
  
  KeeneticMaster::WebServer.start!
rescue Interrupt
  puts "\nShutting down gracefully..."
  exit(0)
rescue => e
  puts "Error starting web server: #{e.message}"
  exit(1)
end 