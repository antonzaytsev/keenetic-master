require_relative '../config/application'

require 'rspec'

RSpec.configure do |config|
  config.order = :random

  Kernel.srand config.seed
end
