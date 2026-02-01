class KeeneticMaster
  class DownloadStartupConfig < BaseClass
    def call
      content = Configuration.keenetic_client.system_config.download
      
      file = Tempfile.new('keenetic-config')
      file.write(content)
      file
    rescue Keenetic::ApiError => e
      logger.error("DownloadStartupConfig failed: #{e.message}")
      Failure(error: e.message)
    end
  end
end
