require_relative 'config/application'

loop do
  p "Начато обновление всех групп и их доменов из config/domains.yml"
  KeeneticMaster::UpdateAllRoutes.call

  p "Все группы обновлены успешно. Перерыв 1 час до следующей проверки."
  sleep 60*60
end
