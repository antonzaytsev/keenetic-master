require 'yaml'
require 'logger'
require_relative 'database'
require_relative 'models'

class MigrateYamlToDb
  def initialize(yaml_file_path = nil)
    @yaml_file_path = yaml_file_path || ENV.fetch('DOMAINS_FILE', 'config/domains.yml')
    @logger = Logger.new(STDOUT)
  end

  def migrate!
    @logger.info("Starting migration from #{@yaml_file_path} to database")
    
    # Ensure database is set up
    Database.setup!
    
    unless File.exist?(@yaml_file_path)
      @logger.error("YAML file not found: #{@yaml_file_path}")
      return false
    end

    yaml_data = load_yaml_data
    return false unless yaml_data

    migrated_groups = 0
    migrated_domains = 0

    yaml_data.each do |group_name, group_data|
      begin
        @logger.info("Migrating group: #{group_name}")
        
        # Check if group already exists
        existing_group = DomainGroup.find(name: group_name)
        if existing_group
          @logger.warn("Group '#{group_name}' already exists, skipping...")
          next
        end

        group = DomainGroup.from_hash(group_name, group_data)
        migrated_groups += 1
        
        domain_count = group.domains_dataset.where(type: 'follow_dns').count
        migrated_domains += domain_count
        @logger.info("Migrated group '#{group_name}' with #{domain_count} domains")
        
      rescue => e
        @logger.error("Failed to migrate group '#{group_name}': #{e.message}")
        @logger.error(e.backtrace.join("\n"))
      end
    end

    @logger.info("Migration completed: #{migrated_groups} groups, #{migrated_domains} domains")
    
    # Backup original file
    backup_yaml_file
    
    true
  end

  def rollback!
    @logger.info("Rolling back migration - clearing database")
    
    Database.connection.transaction do
      Domain.truncate  
      DomainGroup.truncate
    end
    
    @logger.info("Database cleared")
  end

  def verify_migration
    @logger.info("Verifying migration...")
    
    yaml_data = load_yaml_data
    return false unless yaml_data

    all_valid = true

    yaml_data.each do |group_name, group_data|
      db_group = DomainGroup.find(name: group_name)
      unless db_group
        @logger.error("Group '#{group_name}' not found in database")
        all_valid = false
        next
      end

      yaml_hash = normalize_yaml_data(group_data)
      db_hash = db_group.to_hash

      unless hashes_match?(yaml_hash, db_hash)
        @logger.error("Group '#{group_name}' data mismatch")
        @logger.error("YAML: #{yaml_hash.inspect}")
        @logger.error("DB:   #{db_hash.inspect}")
        all_valid = false
      end
    end

    if all_valid
      @logger.info("Migration verification passed")
    else
      @logger.error("Migration verification failed")
    end

    all_valid
  end

  private

  def load_yaml_data
    YAML.load_file(@yaml_file_path) || {}
  rescue => e
    @logger.error("Failed to load YAML file: #{e.message}")
    nil
  end

  def backup_yaml_file
    backup_path = "#{@yaml_file_path}.backup.#{Time.now.strftime('%Y%m%d_%H%M%S')}"
    FileUtils.cp(@yaml_file_path, backup_path)
    @logger.info("Original YAML file backed up to: #{backup_path}")
  rescue => e
    @logger.warn("Failed to backup YAML file: #{e.message}")
  end

  def normalize_yaml_data(data)
    return data if data.is_a?(Array)
    return data unless data.is_a?(Hash)

    result = {}
    result['settings'] = data['settings'] if data['settings']
    result['domains'] = data['domains'] if data['domains']
    result['follow_dns'] = data['follow_dns'] if data['follow_dns']
    
    result
  end

  def hashes_match?(yaml_hash, db_hash)
    # Handle array format
    return yaml_hash.sort == db_hash.sort if yaml_hash.is_a?(Array) && db_hash.is_a?(Array)
    return false if yaml_hash.is_a?(Array) != db_hash.is_a?(Array)

    # Handle hash format
    return false unless yaml_hash.is_a?(Hash) && db_hash.is_a?(Hash)

    # Compare settings
    yaml_settings = yaml_hash['settings'] || {}
    db_settings = db_hash['settings'] || {}
    return false unless yaml_settings == db_settings

    # Compare domains
    yaml_domains = (yaml_hash['domains'] || []).sort
    db_domains = (db_hash['domains'] || []).sort
    return false unless yaml_domains == db_domains

    # Compare follow_dns
    yaml_follow_dns = (yaml_hash['follow_dns'] || []).sort
    db_follow_dns = (db_hash['follow_dns'] || []).sort
    return false unless yaml_follow_dns == db_follow_dns

    true
  end
end

# CLI interface
if __FILE__ == $0
  require 'optparse'

  options = {}
  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    opts.on("-m", "--migrate", "Run migration") do
      options[:migrate] = true
    end

    opts.on("-r", "--rollback", "Rollback migration (clear database)") do
      options[:rollback] = true
    end

    opts.on("-v", "--verify", "Verify migration") do
      options[:verify] = true
    end

    opts.on("-f", "--file FILE", "YAML file path") do |file|
      options[:file] = file
    end

    opts.on("-h", "--help", "Show this help") do
      puts opts
      exit
    end
  end.parse!

  migrator = MigrateYamlToDb.new(options[:file])

  case
  when options[:migrate]
    success = migrator.migrate!
    exit(success ? 0 : 1)
  when options[:rollback]
    migrator.rollback!
  when options[:verify]
    success = migrator.verify_migration
    exit(success ? 0 : 1)
  else
    puts "Please specify an action: --migrate, --rollback, or --verify"
    puts "Use --help for more information"
    exit(1)
  end
end
