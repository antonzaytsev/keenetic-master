require_relative 'update_routes_database'

class KeeneticMaster
  class UpdateAllRoutes < BaseClass
    def call
      updater = UpdateRoutesDatabase.new

      if Configuration.minimize_mode?
        updater.call_minimize(delete_missing: Configuration.delete_missing_routes?)
      else
        updater.call_all
      end
    end
  end
end
