require 'spec_helper'

RSpec.describe KeeneticMaster::Configuration do
  before do
    # Clear any cached configuration
    described_class.instance_variable_set(:@keenetic_credentials, nil)
  end

  describe '.keenetic_credentials' do
    it 'returns credentials hash with required values' do
      credentials = described_class.keenetic_credentials
      
      expect(credentials).to be_a(Hash)
      expect(credentials[:login]).to eq('test_login')
      expect(credentials[:password]).to eq('test_password')
      expect(credentials[:host]).to eq('192.168.1.1')
    end

    it 'caches credentials after first call' do
      expect(ENV).to receive(:fetch).with('KEENETIC_LOGIN').once.and_return('cached_login')
      expect(ENV).to receive(:fetch).with('KEENETIC_PASSWORD').once.and_return('cached_password')
      expect(ENV).to receive(:fetch).with('KEENETIC_HOST').once.and_return('cached_host')

      2.times { described_class.keenetic_credentials }
    end
  end

  describe '.vpn_interfaces' do
    context 'when KEENETIC_VPN_INTERFACES is set' do
      before { ENV['KEENETIC_VPN_INTERFACES'] = 'Interface1,Interface2,Interface3' }
      after { ENV.delete('KEENETIC_VPN_INTERFACES') }

      it 'returns array of interface names' do
        expect(described_class.vpn_interfaces).to eq(['Interface1', 'Interface2', 'Interface3'])
      end
    end

    context 'when KEENETIC_VPN_INTERFACE is set' do
      before { ENV['KEENETIC_VPN_INTERFACE'] = 'SingleInterface' }
      after { ENV.delete('KEENETIC_VPN_INTERFACE') }

      it 'returns array with single interface' do
        expect(described_class.vpn_interfaces).to eq(['SingleInterface'])
      end
    end

    context 'when no interface environment variables are set' do
      it 'returns default Wireguard0' do
        expect(described_class.vpn_interfaces).to eq(['Wireguard0'])
      end
    end
  end

  describe '.dns_servers' do
    context 'when DNS_SERVERS is set' do
      before { ENV['DNS_SERVERS'] = '8.8.8.8,1.1.1.1,9.9.9.9' }
      after { ENV.delete('DNS_SERVERS') }

      it 'returns array of DNS servers' do
        expect(described_class.dns_servers).to eq(['8.8.8.8', '1.1.1.1', '9.9.9.9'])
      end
    end

    context 'when DNS_SERVERS is not set' do
      it 'returns default DNS servers' do
        expect(described_class.dns_servers).to eq(['1.1.1.1', '8.8.8.8'])
      end
    end
  end

  describe '.domains_mask' do
    context 'when DOMAINS_MASK is set' do
      before { ENV['DOMAINS_MASK'] = '24' }
      after { ENV.delete('DOMAINS_MASK') }

      it 'returns the configured mask' do
        expect(described_class.domains_mask).to eq('24')
      end
    end

    context 'when DOMAINS_MASK is not set' do
      it 'returns default mask' do
        expect(described_class.domains_mask).to eq('32')
      end
    end
  end

  describe '.minimize_mode?' do
    context 'when MINIMIZE is true' do
      before { ENV['MINIMIZE'] = 'true' }
      after { ENV.delete('MINIMIZE') }

      it 'returns true' do
        expect(described_class.minimize_mode?).to be true
      end
    end

    context 'when MINIMIZE is false' do
      before { ENV['MINIMIZE'] = 'false' }
      after { ENV.delete('MINIMIZE') }

      it 'returns false' do
        expect(described_class.minimize_mode?).to be false
      end
    end

    context 'when MINIMIZE is not set' do
      it 'returns false by default' do
        expect(described_class.minimize_mode?).to be false
      end
    end
  end

  describe '.delete_missing_routes?' do
    context 'when DELETE_ROUTES is false' do
      before { ENV['DELETE_ROUTES'] = 'false' }
      after { ENV.delete('DELETE_ROUTES') }

      it 'returns false' do
        expect(described_class.delete_missing_routes?).to be false
      end
    end

    context 'when DELETE_ROUTES is true or not set' do
      it 'returns true by default' do
        expect(described_class.delete_missing_routes?).to be true
      end
    end
  end

  describe '.validate!' do
    before { create_test_domains_file }

    context 'when all required environment variables are set' do
      it 'does not raise an error' do
        expect { described_class.validate! }.not_to raise_error
      end

      it 'creates necessary directories' do
        described_class.validate!
        
        expect(File.directory?('tmp/request-dumps')).to be true
        expect(File.directory?('config')).to be true
      end
    end

    context 'when required environment variable is missing' do
      before { ENV.delete('KEENETIC_LOGIN') }
      after { ENV['KEENETIC_LOGIN'] = 'test_login' }

      it 'raises ConfigurationError' do
        expect { described_class.validate! }.to raise_error(
          KeeneticMaster::Configuration::ConfigurationError,
          'Required environment variable KEENETIC_LOGIN is not set'
        )
      end
    end

    context 'when domains file does not exist' do
      before { ENV['DOMAINS_FILE'] = 'non_existent_file.yml' }
      after { ENV['DOMAINS_FILE'] = 'spec/fixtures/test_domains.yml' }

      it 'raises ConfigurationError' do
        expect { described_class.validate! }.to raise_error(
          KeeneticMaster::Configuration::ConfigurationError,
          'Domains file not found: non_existent_file.yml'
        )
      end
    end
  end
end 