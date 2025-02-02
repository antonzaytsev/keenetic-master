require_relative '../config/application'

logger = BaseClass.new.send(:logger, STDOUT)

loop do
  logger.info "Начато обновление всех групп и их доменов из #{ENV.fetch('DOMAINS_FILE')}"
  KeeneticMaster::UpdateAllRoutes.call

  logger.info "Все группы обновлены успешно. Перерыв 1 час до следующей проверки."
  sleep 60*60
end
