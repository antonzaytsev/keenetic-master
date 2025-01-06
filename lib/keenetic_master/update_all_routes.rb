class KeeneticMaster
  class UpdateAllRoutes < ARouteRequest
    def call
      websites = YAML.load_file('./config/domains.yml').keys
      websites.each do |website|
        UpdateDomainRoutes.call(website)
      end
    end
  end
end
