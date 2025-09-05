require_relative 'database'
require 'sequel'

# Establish database connection immediately when this file is loaded
begin
  Database.setup!
rescue => e
  warn "Database connection failed: #{e.message}"
  warn "Models will not be available until database is accessible"
end

# Domain group model
class DomainGroup < Sequel::Model(:domain_groups)
  one_to_many :domains, key: :group_id
  one_to_many :routes, key: :group_id

  def before_update
    self.updated_at = Time.now
    super
  end

  def interfaces_list
    interfaces&.split(',')&.map(&:strip) || []
  end

  def interfaces_list=(list)
    self.interfaces = list.join(',') if list
  end

  # Convert to hash format similar to current YAML structure
  def to_hash
    result = {}
    
    if mask || interfaces
      result['settings'] = {}
      result['settings']['mask'] = mask if mask
      result['settings']['interfaces'] = interfaces if interfaces
    end
    
    regular_domains = domains_dataset.where(type: 'regular').map(:domain)
    follow_dns_domains = domains_dataset.where(type: 'follow_dns').map(:domain)
    
    if regular_domains.any?
      if result.any?
        result['domains'] = regular_domains
      else
        return regular_domains
      end
    end
    
    result['follow_dns'] = follow_dns_domains if follow_dns_domains.any?
    
    result.any? ? result : []
  end

  # Create domain group from hash (for migration from YAML)
  def self.from_hash(name, data)
    group_params = { name: name }
    
    if data.is_a?(Hash)
      if data['settings']
        group_params[:mask] = data['settings']['mask']
        group_params[:interfaces] = data['settings']['interfaces']
      end
      
      group = create(group_params)
      
      # Add regular domains
      if data['domains']
        data['domains'].each do |domain|
          group.add_domain(domain_name: domain, type: 'regular')
        end
      end
      
      # Add follow_dns domains
      if data['follow_dns']
        data['follow_dns'].each do |domain|
          group.add_domain(domain_name: domain, type: 'follow_dns')
        end
      end
    else
      # Simple array format
      group = create(group_params)
      data.each do |domain|
        group.add_domain(domain_name: domain, type: 'regular')
      end
    end
    
    group
  end
end

# Domain model
class Domain < Sequel::Model(:domains)
  many_to_one :domain_group, key: :group_id

  # Custom setter to handle domain field being renamed
  def domain_name
    domain
  end

  def domain_name=(name)
    self.domain = name
  end
end

# Route model
class Route < Sequel::Model(:routes)
  many_to_one :domain_group, key: :group_id

  def before_update
    self.updated_at = Time.now
    super
  end

  def mark_synced!
    update(synced_to_router: true, synced_at: Time.now)
  end

  def mark_unsynced!
    update(synced_to_router: false, synced_at: nil)
  end

  # Convert to format expected by Keenetic API
  def to_keenetic_format
    {
      network: network,
      mask: mask,
      interface: interface,
      comment: comment
    }.compact
  end

  # Find routes that need to be synced
  def self.pending_sync
    where(synced_to_router: false)
  end

  # Find routes that are out of sync (older than X minutes)
  def self.stale(minutes = 60)
    where(synced_to_router: true)
      .where { synced_at < Time.now - (minutes * 60) }
  end
end

# Sync log model for tracking sync operations
class SyncLog < Sequel::Model(:sync_log)
  def self.log_success(operation, resource_type, resource_id = nil)
    create(
      operation: operation,
      resource_type: resource_type,
      resource_id: resource_id,
      success: true
    )
  end

  def self.log_error(operation, resource_type, error_message, resource_id = nil)
    create(
      operation: operation,
      resource_type: resource_type,
      resource_id: resource_id,
      success: false,
      error_message: error_message
    )
  end

  def self.recent_failures(hours = 24)
    where(success: false)
      .where { created_at > Time.now - (hours * 3600) }
      .order(:created_at)
  end
end

# DNS Processing log model for tracking DNS log processing events
class DnsProcessingLog < Sequel::Model(:dns_processing_log)
  def self.log_processing_event(action:, domain:, group_name:, routes_count: 0, network: nil, mask: nil, interface: nil, comment: nil, ip_addresses: nil)
    create(
      action: action,
      domain: domain,
      group_name: group_name,
      network: network,
      mask: mask,
      interface: interface,
      comment: comment,
      ip_addresses: ip_addresses&.is_a?(Array) ? ip_addresses.join(',') : ip_addresses,
      routes_count: routes_count
    )
  end

  def self.recent_logs(limit: 100)
    order(Sequel.desc(:created_at)).limit(limit)
  end

  def self.by_group(group_name)
    where(group_name: group_name).order(Sequel.desc(:created_at))
  end

  def self.by_action(action)
    where(action: action).order(Sequel.desc(:created_at))
  end

  def self.search(query)
    where(Sequel.ilike(:domain, "%#{query}%"))
      .or(Sequel.ilike(:group_name, "%#{query}%"))
      .or(Sequel.ilike(:comment, "%#{query}%"))
      .order(Sequel.desc(:created_at))
  end

  def ip_addresses_array
    ip_addresses&.split(',') || []
  end
end
