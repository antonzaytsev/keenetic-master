require 'bundler/setup'
Bundler.require(:default)

require 'dotenv/load'
require "active_support/core_ext/object"
require "active_support/json"
require 'logger'
require 'fileutils'

class ApplicationLoader
  class << self
    def load_application
      load_project_files
      setup_directories
      check_settings
    end

    def reload!(print = true)
      puts 'Reloading ...' if print
      load_project_files
      true
    rescue StandardError => error
      puts "Error reloading: #{error.message}"
      false
    end

    private

    def load_project_files
      root_dir = File.expand_path('../', __dir__)
      reload_dirs = %w[lib]

      reload_dirs.each do |dir|
        Dir.glob("#{root_dir}/#{dir}/**/*.rb").sort.each { |file| load(file) }
      end
    end

    def setup_directories
      %w[tmp/logs tmp/request-dumps].each do |dir|
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
      end
    end

    def check_settings
      missing = KeeneticMaster::Configuration.missing_settings
      if missing.any?
        puts "Notice: Router settings not configured: #{missing.join(', ')}"
        puts "Configure them via the Settings page at /settings"
      end
    end
  end
end

# Load the application
ApplicationLoader.load_application

# Create convenience methods for console usage
def reload!(print = true)
  ApplicationLoader.reload!(print)
end

