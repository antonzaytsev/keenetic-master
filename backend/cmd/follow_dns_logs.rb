require_relative '../config/application'

# Base API URL can be set via environment variable or use default
base_api_url = ENV['DNS_LOGS_API_URL'] || 'http://192.168.0.30:8080/api/search'

logger = BaseClass.new.send(:logger, STDOUT)

logger.info "Начато слежение за DNS логами через API: #{base_api_url}"
KeeneticMaster::FollowDnsLogs.call(base_api_url)
logger.info "Окончено слежение за DNS логами"
