class KeeneticMaster
  class UpdateAllRoutes < BaseClass
    def call
      websites = YAML.load_file(ENV.fetch('DOMAINS_FILE')).keys
      websites.each do |website|
        UpdateDomainRoutes.call(website)
      end
    end
  end
end
