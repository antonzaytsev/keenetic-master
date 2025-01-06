class KeeneticMaster
  class << self
    def system
      response = Client.get('rci/show/system')
      Rails.logger.error("Unsucessful response #{response.code}") if response.code != 200

      JSON.parse(response.body)
    end

    def interface
      response = Client.get('rci/show/interface')
      # Rails.logger.error("Unsucessful response #{response.code}") if response.code != 200

      # JSON.parse(response.body)
    end
  end
end
