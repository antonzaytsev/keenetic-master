require_relative '../config/application'

logger = BaseClass.new.send(:logger, STDOUT)

if ARGV.any?
  logger.info "Начато обновление доменов для групп #{ARGV.join(', ')}"
  response = KeeneticMaster::UpdateDomainRoutesMinimize.call(ARGV, delete_missing: ENV['DELETE_ROUTES'].nil? || ENV['DELETE_ROUTES'] == 'true')
  if response.failure?
    logger.info "Ошибка: #{response.failure[:message]}"
  else
    p response.value![:message]
  end
else
  logger.info "Начато обновление всех групп и их доменов из #{ENV.fetch('DOMAINS_FILE')}"
  KeeneticMaster::UpdateAllRoutes.call
  logger.info "Все группы обновлены успешно"
end
