require 'spec_helper'

require_relative '../../lib/keenetic_master/delete_route'
require_relative '../../lib/keenetic_master/client'

RSpec.describe KeeneticMaster::DeleteRoute do
  let(:delete_route) { described_class.new }
  let(:client) { double('Client') }

  before do
    allow(KeeneticMaster::Client).to receive(:new).and_return(client)
  end

  it 'returns success when called with valid params and response code is 200' do
    allow(client).to receive(:post_rci).and_return(double(code: 200))

    result = delete_route.call(host: '192.168.1.1', network: '192.168.1.0', mask: '255.255.255.0')
    expect(result).to be_success
  end

  it 'returns failure when response code is not 200' do
    allow(client).to receive(:post_rci).and_return(double(code: 403))

    result = delete_route.call(host: '192.168.1.1', network: '192.168.1.0', mask: '255.255.255.0')
    expect(result).to be_failure
  end

  it 'returns success when called with missing params' do
    allow(client).to receive(:post_rci).and_return(double(code: 200))

    result = delete_route.call
    expect(result).to be_success
  end
end
