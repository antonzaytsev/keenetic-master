class KeeneticMaster
  class << self
    def system
      response = Client.get('rci/show/system')
      logger.error("Unsuccessful response #{response.code}") if response.code != 200

      JSON.parse(response.body)
    end

    def interface
      response = Client.get('rci/show/interface')
      if response.code != 200
        return Dry::Monads::Result::Failure.new(message: "Неуспешный запрос на получение интерфейсов. Код #{response.code}")
      end

      Dry::Monads::Result::Success.new(JSON.parse(response.body))
    end
  end
end
