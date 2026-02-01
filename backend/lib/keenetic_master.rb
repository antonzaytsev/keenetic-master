class KeeneticMaster
  class << self
    def system
      Configuration.keenetic_client.system.info
    rescue Keenetic::ApiError => e
      logger.error("Failed to get system info: #{e.message}")
      {}
    end

    def interface
      result = Configuration.keenetic_client.network.interfaces
      Dry::Monads::Result::Success.new(result)
    rescue Keenetic::ApiError => e
      Dry::Monads::Result::Failure.new(message: "Failed to get interfaces: #{e.message}")
    end

    private

    def logger
      @logger ||= BaseClass.new.send(:logger)
    end
  end
end
