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
    
    follow_dns_domains = domains_dataset.where(type: 'follow_dns').map(:domain)
    
    # Only include follow_dns domains (regular domains are no longer supported)
    if follow_dns_domains.any?
      if result.any?
        # We have settings, so use hash format
        result['follow_dns'] = follow_dns_domains
      else
        # No settings - use simple hash format with follow_dns
        result['follow_dns'] = follow_dns_domains
      end
    end
    
    # Return result if it has content, otherwise return empty array for backward compatibility
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

      # Only add follow_dns domains (regular domains are no longer supported)
      if data['follow_dns']
        data['follow_dns'].each do |domain|
          group.add_domain(domain: domain, type: 'follow_dns')
        end
      end
      
      # Ignore regular domains - they are no longer supported
      if data['domains']
        # Log warning if regular domains are provided (they will be ignored)
        warn("Ignoring regular domains in group '#{name}' - only DNS monitored domains are supported")
      end
    else
      # Simple array format - treat as follow_dns
      group = create(group_params)
      data.each do |domain|
        group.add_domain(domain: domain, type: 'follow_dns')
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

# Setting model for application configuration
class Setting < Sequel::Model(:settings)
  KEENETIC_SETTINGS = %w[
    keenetic_login
    keenetic_password
    keenetic_host
    keenetic_vpn_interface
  ].freeze

  SETTING_DESCRIPTIONS = {
    'keenetic_login' => 'Keenetic router login username',
    'keenetic_password' => 'Keenetic router login password',
    'keenetic_host' => 'Keenetic router host address (e.g., 192.168.1.1)',
    'keenetic_vpn_interface' => 'Default VPN interface for routing (e.g., Wireguard0)'
  }.freeze

  def before_update
    self.updated_at = Time.now
    super
  end

  def self.get(key)
    setting = find(key: key.to_s)
    setting&.value
  end

  def self.set(key, value, description: nil)
    setting = find_or_create(key: key.to_s)
    setting.update(value: value.to_s)
    setting.update(description: description) if description
    setting
  end

  def self.get_all_keenetic_settings
    KEENETIC_SETTINGS.each_with_object({}) do |key, hash|
      setting = find(key: key)
      hash[key] = {
        value: setting&.value,
        description: SETTING_DESCRIPTIONS[key],
        updated_at: setting&.updated_at&.iso8601
      }
    end
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
