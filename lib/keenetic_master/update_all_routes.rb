class KeeneticMaster
  class UpdateAllRoutes < BaseClass
    def call
      websites = YAML.load_file(ENV.fetch('DOMAINS_FILE'))&.keys || []

      if ENV.fetch('MINIMIZE', false)
        UpdateDomainRoutesMinimize.call(websites, delete_missing: ENV['DELETE_ROUTES'].nil? || ENV['DELETE_ROUTES'] == 'true')
      else
        websites.each do |website|
          UpdateDomainRoutes.call(website)
        end
      end
    end
  end
end
