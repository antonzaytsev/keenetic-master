require_relative '../config/application'

dns_logs_path = ENV['DNS_LOGS_PATH']
if !dns_logs_path.present? || !File.exist?(dns_logs_path) || !File.readable?(dns_logs_path)
  puts "Не указаны или недоступен файл в переменной окружения DNS_LOGS_PATH `#{dns_logs_path}`"
  return
end

logger = BaseClass.new.send(:logger, STDOUT)

logger.info "Начато слежение за логами DNS в #{dns_logs_path}"
KeeneticMaster::FollowDnsLogs.call(dns_logs_path)
logger.info "Окончено слежение за логами DNS в #{dns_logs_path}"
