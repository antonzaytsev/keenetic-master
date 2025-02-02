require_relative '../config/application'

logger = BaseClass.new.send(:logger, STDOUT)

group = ARGV[0]
if group
  logger.info "Начато обновление доменов для группы #{group}"
  response = KeeneticMaster::UpdateDomainRoutes.call(group, ARGV[1])
  if response.failure?
    logger.info "Ошибка: #{response.failure[:message]}"
  else
    print response.value![:message]
  end
else
  logger.info "Начато обновление всех групп и их доменов из #{ENV.fetch('DOMAINS_FILE')}"
  KeeneticMaster::UpdateAllRoutes.call
  logger.info "Все группы обновлены успешно"
end
