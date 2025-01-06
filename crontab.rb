require_relative 'config/application'

loop do
  KeeneticMaster::UpdateAllRoutes.call

  p "All routes updated. Sleeping for 1 hour."
  sleep 60*60
end
