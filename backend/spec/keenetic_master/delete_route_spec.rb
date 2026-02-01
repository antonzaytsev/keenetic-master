require 'spec_helper'

require_relative '../../lib/keenetic_master/delete_route'

RSpec.describe KeeneticMaster::DeleteRoute do
  let(:delete_route) { described_class.new }
  let(:keenetic_client) { double('Keenetic::Client') }
  let(:routes) { double('Routes') }

  before do
    allow(KeeneticMaster::Configuration).to receive(:keenetic_client).and_return(keenetic_client)
    allow(keenetic_client).to receive(:routes).and_return(routes)
  end

  it 'returns success when called with valid host param' do
    allow(routes).to receive(:delete).with(host: '192.168.1.1')

    result = delete_route.call(host: '192.168.1.1')
    expect(result).to be_success
  end

  it 'returns success when called with network and mask params' do
    allow(routes).to receive(:delete).with(network: '192.168.1.0/24')

    result = delete_route.call(network: '192.168.1.0', mask: '255.255.255.0')
    expect(result).to be_success
  end

  it 'returns failure when API raises an error' do
    allow(routes).to receive(:delete).and_raise(Keenetic::ApiError.new('Route not found'))

    result = delete_route.call(host: '192.168.1.1')
    expect(result).to be_failure
  end
end
