class KeeneticMaster
  class UpdateAllRoutes < BaseClass
    def call
      websites = YAML.load_file(ENV.fetch('DOMAINS_FILE'))&.keys || []

      if ENV.fetch('MINIMIZE', false)
        UpdateDomainRoutesMinimize.call(websites)
      else
        websites.each do |website|
          UpdateDomainRoutes.call(website)
        end
      end
    end
  end
end
