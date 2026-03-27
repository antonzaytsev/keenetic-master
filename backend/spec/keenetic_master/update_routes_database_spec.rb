require 'spec_helper'

RSpec.describe KeeneticMaster::UpdateRoutesDatabase do
  include Dry::Monads[:result]

  let(:updater) { described_class.new }

  describe '#call (single group)' do
    context 'when group is disabled' do
      let(:group) { instance_double(DomainGroup, name: 'test', enabled: false) }

      before do
        allow(DomainGroup).to receive(:find).with(name: 'test').and_return(group)
        allow(updater).to receive(:logger).and_return(double(info: true, warn: true, error: true))
      end

      it 'returns success with skipped message' do
        result = updater.call('test')
        expect(result).to be_success
        expect(result.value![:message]).to include('disabled')
      end

      it 'does not call RouterRoutesManager' do
        routes_manager = instance_double(KeeneticMaster::RouterRoutesManager)
        allow(KeeneticMaster::RouterRoutesManager).to receive(:new).and_return(routes_manager)
        expect(routes_manager).not_to receive(:push_group_routes!)
        updater.call('test')
      end
    end

    context 'when group does not exist' do
      before do
        allow(DomainGroup).to receive(:find).with(name: 'missing').and_return(nil)
        allow(updater).to receive(:logger).and_return(double(info: true, warn: true, error: true))
      end

      it 'returns failure' do
        result = updater.call('missing')
        expect(result).to be_failure
      end
    end
  end

  describe '#call_all' do
    let(:enabled_group) { instance_double(DomainGroup, name: 'enabled_grp', enabled: true) }
    let(:disabled_group) { instance_double(DomainGroup, name: 'disabled_grp', enabled: false) }

    before do
      allow(DomainGroup).to receive(:all).and_return([enabled_group, disabled_group])
      allow(updater).to receive(:logger).and_return(double(info: true, warn: true, error: true))
      allow(updater).to receive(:call).with('enabled_grp').and_return(
        Success(group: 'enabled_grp', added: 1, deleted: 0, message: 'ok')
      )
    end

    it 'skips disabled groups' do
      expect(updater).not_to receive(:call).with('disabled_grp')
      updater.call_all
    end

    it 'processes enabled groups' do
      expect(updater).to receive(:call).with('enabled_grp').and_return(
        Success(group: 'enabled_grp', added: 1, deleted: 0, message: 'ok')
      )
      updater.call_all
    end
  end
end
