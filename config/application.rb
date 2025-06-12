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
      validate_configuration
      setup_directories
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

    def validate_configuration
      KeeneticMaster::Configuration.validate!
    rescue KeeneticMaster::Configuration::ConfigurationError => e
      puts "Configuration Error: #{e.message}"
      puts "Please check your .env file and ensure all required variables are set."
      exit(1)
    end

    def setup_directories
      %w[tmp/logs tmp/request-dumps].each do |dir|
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
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

def verify_env_set
  raise "ENV variable KEENETIC_LOGIN is not set" if ENV['KEENETIC_LOGIN'].blank?
  raise "ENV variable KEENETIC_PASSWORD is not set" if ENV['KEENETIC_PASSWORD'].blank?
  raise "ENV variable KEENETIC_HOST is not set" if ENV['KEENETIC_HOST'].blank?
end
verify_env_set
