class KeeneticMaster
  class DownloadStartupConfig < ARouteRequest
    PATH = 'ci/startup-config.txt'

    def call
      response = Client.new.get(PATH)
      return Failure if response.code != 200

      file = Tempfile.new('keenetic-config')
      file.write(response.body)
      file
    end
  end
end
