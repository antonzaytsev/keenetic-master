require 'bundler/setup'
Bundler.require(:default, :test)

require 'webmock/rspec'
require 'vcr'

# Disable real HTTP connections except for localhost
WebMock.disable_net_connect!(allow_localhost: true)

# Load the application
require_relative '../config/application'

# VCR configuration for recording HTTP interactions
VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :typhoeus
  config.configure_rspec_metadata!
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # This option will default to `:apply_to_host_groups` in RSpec 4
  config.filter_run_when_matching :focus

  # Allows RSpec to persist some state between runs
  config.example_status_persistence_file_path = "spec/examples.txt"

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  # Run specs in random order to surface order dependencies
  config.order = :random
  Kernel.srand config.seed

  # Clear logs before each test
  config.before(:each) do
    FileUtils.rm_rf('tmp/logs')
    FileUtils.rm_rf('tmp/request-dumps')
  end

  # Set up test environment variables
  config.before(:all) do
    ENV['KEENETIC_LOGIN'] = 'test_login'
    ENV['KEENETIC_PASSWORD'] = 'test_password'
    ENV['KEENETIC_HOST'] = '192.168.1.1'
    ENV['DOMAINS_FILE'] = 'spec/fixtures/test_domains.yml'
    ENV['LOG_LEVEL'] = 'ERROR'
  end
end

# Helper methods for tests
module TestHelpers
  def fixture_path(filename)
    File.join('spec', 'fixtures', filename)
  end

  def load_fixture(filename)
    File.read(fixture_path(filename))
  end

  def stub_keenetic_auth
    stub_request(:get, "http://192.168.1.1/auth")
      .to_return(
        status: 401,
        headers: {
          'X-NDM-Realm' => 'test_realm',
          'X-NDM-Challenge' => 'test_challenge'
        }
      )

    stub_request(:post, "http://192.168.1.1/auth")
      .to_return(status: 200)
  end

  def stub_keenetic_routes_request
    stub_request(:get, "http://192.168.1.1/rci/show/ip/route")
      .to_return(
        status: 200,
        body: '[]',
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  def create_test_domains_file
    domains_content = {
      'test_group' => {
        'settings' => {
          'mask' => '32',
          'interfaces' => 'Wireguard0'
        },
        'domains' => ['example.com', 'test.com']
      }
    }

    FileUtils.mkdir_p('spec/fixtures')
    File.write('spec/fixtures/test_domains.yml', domains_content.to_yaml)
  end
end

RSpec.configure do |config|
  config.include TestHelpers
end
