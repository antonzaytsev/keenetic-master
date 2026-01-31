require_relative '../config/application'

logger = BaseClass.new.send(:logger, STDOUT)

client = ARGV[0]
policy_name = ARGV[1]
if client
  response = KeeneticMaster::ToggleClientPolicy.call(client, policy_name)
  if response.failure?
    logger.info "Ошибка: #{response.failure[:message]}"
  else
    p response.value![:message]
  end
else
  logger.info "Необходимо указать клиента"
end
