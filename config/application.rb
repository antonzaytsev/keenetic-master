require 'bundler/setup'
Bundler.require(:default)

require 'dotenv/load'
require "active_support/core_ext/object"
require "active_support/json"

def load_files
  root_dir = File.expand_path('../', __dir__)

  # Directories within the project that should be reloaded.
  reload_dirs = %w{lib}

  # Loop through and reload every file in all relevant project directories.
  reload_dirs.each do |dir|
    Dir.glob("#{root_dir}/#{dir}/**/*.rb").each { |f| load(f) }
  end
end
load_files

def reload!(print = true)
  puts 'Reloading ...' if print

  load_files

  true
end

def verify_env_set
  raise "ENV variable KEENETIC_LOGIN is not set" if ENV['KEENETIC_LOGIN'].blank?
  raise "ENV variable KEENETIC_PASSWORD is not set" if ENV['KEENETIC_PASSWORD'].blank?
  raise "ENV variable KEENETIC_HOST is not set" if ENV['KEENETIC_HOST'].blank?
end
verify_env_set
