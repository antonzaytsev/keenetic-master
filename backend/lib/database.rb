require 'sequel'
require 'pg'
require 'fileutils'

class Database
  class << self
    attr_reader :db

    def setup!
      connection_string = build_connection_string
      
      @db = Sequel.connect(connection_string)
      
      # Set the database connection for all Sequel models
      Sequel::Model.db = @db
      
      run_migrations!
      
      @db
    end

    def connection
      return @db if @db
      
      # Lazy initialization - setup database when first accessed
      setup!
    end

    private

    def build_connection_string
      host = ENV.fetch('DATABASE_HOST', 'localhost')
      port = ENV.fetch('DATABASE_PORT', '5433')
      database = ENV.fetch('DATABASE_NAME', 'keenetic_master')
      username = ENV.fetch('DATABASE_USERNAME', 'postgres')
      password = ENV.fetch('DATABASE_PASSWORD', 'postgres')

      "postgres://#{username}:#{password}@#{host}:#{port}/#{database}"
    end

    def run_migrations!
      create_domain_groups_table unless @db.tables.include?(:domain_groups)
      create_domains_table unless @db.tables.include?(:domains)
      create_dns_processing_log_table unless @db.tables.include?(:dns_processing_log)
      
      # Drop routes and sync_log tables if they exist (no longer needed - routes stored on Keenetic)
      @db.drop_table(:routes) if @db.tables.include?(:routes)
      @db.drop_table(:sync_log) if @db.tables.include?(:sync_log)
    end

    def tables_exist?
      @db.tables.include?(:domain_groups)
    end

    def create_domain_groups_table
      @db.create_table :domain_groups do
        primary_key :id
        String :name, unique: true, null: false
        String :mask
        String :interfaces
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
        DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
        
        index :name
      end
    end

    def create_domains_table
      @db.create_table :domains do
        primary_key :id
        foreign_key :group_id, :domain_groups, on_delete: :cascade
        String :domain, null: false
        String :type, default: 'follow_dns' # Only follow_dns is supported
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
        
        index [:group_id, :domain]
        index :type
      end
    end

    def create_dns_processing_log_table
      @db.create_table :dns_processing_log do
        primary_key :id
        String :action, null: false # 'added', 'skipped', 'processed'
        String :domain, null: false
        String :group_name, null: false
        String :network
        String :mask
        String :interface
        String :comment
        String :ip_addresses
        Integer :routes_count, default: 0
        DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
        
        index :created_at
        index :action
        index :group_name
        index :domain
      end
    rescue => e
      # Log error but don't crash if table already exists
      puts "Warning: Could not create dns_processing_log table: #{e.message}"
      raise e unless e.message.include?('already exists')
    end

    # Method to manually create missing tables
    def self.create_missing_tables!
      setup! unless @db
      
      missing_tables = []
      
      unless @db.tables.include?(:dns_processing_log)
        missing_tables << :dns_processing_log
        @db.create_table :dns_processing_log do
          primary_key :id
          String :action, null: false
          String :domain, null: false
          String :group_name, null: false
          String :network
          String :mask
          String :interface
          String :comment
          String :ip_addresses
          Integer :routes_count, default: 0
          DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
          
          index :created_at
          index :action
          index :group_name
          index :domain
        end
      end
      
      missing_tables
    rescue => e
      puts "Error creating missing tables: #{e.message}"
      []
    end
  end
end
