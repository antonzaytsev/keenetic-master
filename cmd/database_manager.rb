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
      
    Options:
      -f, --file FILE  YAML file path for migration
      -h, --help       Show this help
      
    Examples:
      ruby cmd/database_manager.rb setup
      ruby cmd/database_manager.rb migrate -f config/domains.yml
      ruby cmd/database_manager.rb sync
  HELP
end

def setup_database
  puts "Setting up database..."
  Database.setup!
  puts "✅ Database setup completed"
  
  group_count = DomainGroup.count
  domain_count = Domain.count
  route_count = Route.count
  
  puts "📊 Database status:"
  puts "  - Groups: #{group_count}"
  puts "  - Domains: #{domain_count}"
  puts "  - Routes: #{route_count}"
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
    puts "  - Generated routes: #{stats[:generated]}"
    puts "  - Synced to router: #{stats[:synced_to_router]}"
    puts "  - Reconciled from router: #{stats[:reconciled_from_router]}"
  else
    puts "❌ Sync failed: #{result.failure}"
    exit(1)
  end
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
    puts "  - routes: #{Route.count} records"
    puts "  - sync_log: #{SyncLog.count} records"
    puts
    
    # Recent sync activity
    recent_syncs = SyncLog.recent_failures(24).count
    if recent_syncs > 0
      puts "⚠️  #{recent_syncs} sync failures in last 24 hours"
    end
    
    # Pending routes
    pending_routes = Route.pending_sync.count
    if pending_routes > 0
      puts "📤 #{pending_routes} routes pending sync to router"
    else
      puts "✅ All routes are synced"
    end
    
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
when nil
  puts "No command specified"
  show_help
  exit(1)
else
  puts "Unknown command: #{command}"
  show_help
  exit(1)
end
