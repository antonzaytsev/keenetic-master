require 'spec_helper'

RSpec.describe KeeneticMaster::Configuration do
  before do
    # Clear any cached configuration
    described_class.instance_variable_set(:@keenetic_client, nil)
    
    # Ensure test settings are in database
    Setting.set('keenetic_login', 'test_login')
    Setting.set('keenetic_password', 'test_password')
    Setting.set('keenetic_host', '192.168.1.1')
    Setting.set('keenetic_vpn_interface', 'Wireguard0')
  end

  describe '.vpn_interface' do
    context 'when setting is configured in database' do
      before { Setting.set('keenetic_vpn_interface', 'TestInterface') }

      it 'returns the configured interface' do
        expect(described_class.vpn_interface).to eq('TestInterface')
      end
    end

    context 'when setting is not configured' do
      before { Setting.find(key: 'keenetic_vpn_interface')&.destroy }

      it 'returns default Wireguard0' do
        expect(described_class.vpn_interface).to eq('Wireguard0')
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
    context 'when domains_mask is set in database' do
      before { Setting.set('domains_mask', '24') }
      after { Setting.find(key: 'domains_mask')&.destroy }

      it 'returns the database value' do
        expect(described_class.domains_mask).to eq('24')
      end

      it 'takes priority over ENV' do
        ENV['DOMAINS_MASK'] = '16'
        expect(described_class.domains_mask).to eq('24')
        ENV.delete('DOMAINS_MASK')
      end
    end

    context 'when DOMAINS_MASK env is set but database is not' do
      before do
        Setting.find(key: 'domains_mask')&.destroy
        ENV['DOMAINS_MASK'] = '24'
      end
      after { ENV.delete('DOMAINS_MASK') }

      it 'falls back to ENV value' do
        expect(described_class.domains_mask).to eq('24')
      end
    end

    context 'when neither database nor ENV is set' do
      before { Setting.find(key: 'domains_mask')&.destroy }

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

  describe '.configured?' do
    context 'when all required settings are configured' do
      it 'returns true' do
        expect(described_class.configured?).to be true
      end
    end

    context 'when required setting is missing' do
      before { Setting.find(key: 'keenetic_login')&.destroy }

      it 'returns false' do
        expect(described_class.configured?).to be false
      end
    end
  end

  describe '.missing_settings' do
    context 'when all settings are configured' do
      it 'returns empty array' do
        expect(described_class.missing_settings).to be_empty
      end
    end

    context 'when some settings are missing' do
      before do
        Setting.find(key: 'keenetic_login')&.destroy
        Setting.find(key: 'keenetic_host')&.destroy
      end

      it 'returns array of missing setting keys' do
        expect(described_class.missing_settings).to contain_exactly('keenetic_host', 'keenetic_login')
      end
    end
  end

  describe '.validate_required_settings!' do
    context 'when all required settings are configured' do
      it 'does not raise an error' do
        expect { described_class.validate_required_settings! }.not_to raise_error
      end
    end

    context 'when required setting is missing' do
      before { Setting.find(key: 'keenetic_login')&.destroy }

      it 'raises NotConfiguredError' do
        expect { described_class.validate_required_settings! }.to raise_error(
          KeeneticMaster::Configuration::NotConfiguredError,
          /Router not configured.*keenetic_login/
        )
      end
    end
  end
end
