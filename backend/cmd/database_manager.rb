#!/usr/bin/env ruby

require_relative '../config/application'
require_relative '../lib/database'
require_relative '../lib/models'
require_relative '../lib/migrate_yaml_to_db'
require_relative '../lib/keenetic_master/database_router_sync'
require 'optparse'

def show_help
  puts <<~HELP
    Database Manager for Keenetic Master

    Commands:
      setup           Initialize database and run migrations
      migrate         Migrate YAML data to database
      rollback        Clear all database data
      verify          Verify migration integrity
      sync            Sync database with router
      status          Show database status
      convert-regular-to-dns  Convert all regular domains to DNS monitoring type
      
    Options:
      -f, --file FILE  YAML file path for migration
      -h, --help       Show this help
      
    Examples:
      ruby cmd/database_manager.rb setup
      ruby cmd/database_manager.rb migrate -f config/domains.yml
      ruby cmd/database_manager.rb sync
      ruby cmd/database_manager.rb convert-regular-to-dns
  HELP
end

def setup_database
  puts "Setting up database..."
  Database.setup!
  puts "✅ Database setup completed"
  
  group_count = DomainGroup.count
  domain_count = Domain.count
  
  puts "📊 Database status:"
  puts "  - Groups: #{group_count}"
  puts "  - Domains: #{domain_count}"
end

def migrate_yaml(yaml_file = nil)
  puts "Starting YAML to database migration..."
  
  migrator = MigrateYamlToDb.new(yaml_file)
  success = migrator.migrate!
  
  if success
    puts "✅ Migration completed successfully"
    verify_migration(migrator)
  else
    puts "❌ Migration failed"
    exit(1)
  end
end

def rollback_database
  puts "Rolling back database..."
  
  migrator = MigrateYamlToDb.new
  migrator.rollback!
  
  puts "✅ Database cleared"
end

def verify_migration(migrator = nil)
  puts "Verifying migration..."
  
  migrator ||= MigrateYamlToDb.new
  success = migrator.verify_migration
  
  if success
    puts "✅ Migration verification passed"
  else
    puts "❌ Migration verification failed"
    exit(1)
  end
end

def sync_database
  puts "Starting database-router sync..."
  
  sync_service = KeeneticMaster::DatabaseRouterSync.new
  result = sync_service.full_sync!
  
  if result.success?
    stats = result.value!
    puts "✅ Sync completed successfully:"
    puts "  - Groups processed: #{stats[:groups_processed]}"
    puts "  - Routes added: #{stats[:total_added]}"
    puts "  - Routes deleted: #{stats[:total_deleted]}"
  else
    puts "❌ Sync failed: #{result.failure}"
    exit(1)
  end
end

def convert_regular_to_dns
  puts "Converting all regular domains to DNS monitoring type..."
  
  Database.setup!
  
  regular_domains = Domain.where(type: 'regular').all
  converted_count = 0
  
  if regular_domains.empty?
    puts "✅ No regular domains found to convert"
    return
  end
  
  puts "Found #{regular_domains.count} regular domains to convert"
  
  Database.connection.transaction do
    regular_domains.each do |domain|
      # Check if domain already exists as follow_dns in the same group
      existing = Domain.find(group_id: domain.group_id, domain: domain.domain, type: 'follow_dns')
      
      if existing
        # Domain already exists as follow_dns, just delete the regular one
        domain.destroy
        puts "  Removed duplicate regular domain: #{domain.domain} (already exists as DNS monitored)"
      else
        # Convert to follow_dns
        domain.update(type: 'follow_dns')
        converted_count += 1
        puts "  Converted: #{domain.domain}"
      end
    end
  end
  
  puts "✅ Conversion completed: #{converted_count} domains converted to DNS monitoring"
end

def show_status
  begin
    Database.setup!
    
    puts "📊 Database Status"
    puts "=" * 50
    
    # Connection info
    puts "Connection: PostgreSQL"
    puts "Host: #{ENV.fetch('DATABASE_HOST', 'localhost')}"
    puts "Port: #{ENV.fetch('DATABASE_PORT', '5433')}"
    puts "Database: #{ENV.fetch('DATABASE_NAME', 'keenetic_master')}"
    puts
    
    # Tables and counts
    puts "Tables:"
    puts "  - domain_groups: #{DomainGroup.count} records"
    puts "  - domains: #{Domain.count} records"
    puts
    
    # Domain type breakdown
    follow_dns_count = Domain.where(type: 'follow_dns').count
    puts "Domain Types:"
    puts "  - DNS Monitored: #{follow_dns_count}"
    puts
    
    # Routes are now stored on Keenetic router directly
    puts "Routes: Stored on Keenetic router (use /api/router-routes to view)"
    
  rescue => e
    puts "❌ Database connection failed: #{e.message}"
    exit(1)
  end
end

# Main script
options = {}
command = nil

OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} COMMAND [options]"
  
  opts.on("-f", "--file FILE", "YAML file path") do |file|
    options[:file] = file
  end
  
  opts.on("-h", "--help", "Show this help") do
    show_help
    exit
  end
end.parse!

command = ARGV[0]

case command
when 'setup'
  setup_database
when 'migrate'
  migrate_yaml(options[:file])
when 'rollback'
  rollback_database
when 'verify'
  verify_migration
when 'sync'
  sync_database
when 'status'
  show_status
when 'convert-regular-to-dns'
  convert_regular_to_dns
when nil
  puts "No command specified"
  show_help
  exit(1)
else
  puts "Unknown command: #{command}"
  show_help
  exit(1)
end
