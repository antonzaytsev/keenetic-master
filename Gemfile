source "https://rubygems.org"

ruby "~> 3.0"

# Core functionality
gem "typhoeus", "~> 1.4"
gem "watir", "~> 7.0"
gem "dnsruby", "~> 1.70"
gem "activesupport", ">= 7.0"
gem "dry-initializer", "~> 3.1"
gem "dry-monads", "~> 1.6"
gem "progress_bar", "~> 1.3"

# Configuration and environment
gem "dotenv", "~> 2.8"

# Data handling
gem "json", "~> 2.6"

group :development do
  gem "pry", "~> 0.14"
  gem "reline", "~> 0.3"
  gem "rubocop", "~> 1.50"
  gem "rubocop-performance", "~> 1.16"
  gem "rubocop-rspec", "~> 2.20"
end

group :test do
  gem "rspec", "~> 3.12"
  gem "webmock", "~> 3.18"
  gem "vcr", "~> 6.1"
  gem "factory_bot", "~> 6.2"
end

group :development, :test do
  gem "byebug", "~> 11.1"
end
