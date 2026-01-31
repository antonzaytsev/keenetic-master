require 'yaml'

RSpec.describe KeeneticMaster::UpdateDomainRoutes do
  let(:update_domain_routes) { described_class.new }
  let(:group_name) { 'test_group' }
  let(:default_interface) { 'test_interface' }
  let(:existing_routes) { [{ network: '192.168.1.0', mask: '255.255.255.0' }] }
  let(:eventual_routes) { [{ network: '192.168.1.0', mask: '255.255.255.0' }] }
  let(:to_delete) { [] }
  let(:to_add) { [] }

  before do
    get_all_routes_instance = instance_double(GetAllRoutes)
    allow(GetAllRoutes).to receive(:new).and_return(get_all_routes_instance)
    allow(get_all_routes_instance).to receive(:call).and_return(Success(message: existing_routes))

    (update_domain_routes).to receive(:retrieve_existing_routes).and_return(existing_routes)
    allow(update_domain_routes).to receive(:routes_to_exist).and_return(eventual_routes)
    allow(KeeneticMaster::DeleteRoutes).to receive(:call).and_return(Dry::Types::Mixin::Success())
    allow(KeeneticMaster::AddRoutes).to receive(:call).and_return(Success())
    allow(update_domain_routes).to receive(:logger).and_return(double(info: true))
  end

  it 'successfully processes the group' do
    result = update_domain_routes.call(group_name, default_interface)
    expect(result).to be_success
    expect(result.value!).to include(added: to_add.size, deleted: to_delete.size, eventually: eventual_routes.size)
  end

  it 'returns failure if AddRoutes fails' do
    allow(KeeneticMaster::AddRoutes).to receive(:call).and_return(Failure('error'))
    result = update_domain_routes.call(group_name, default_interface)
    expect(result).to be_failure
  end

  it 'logs the correct message' do
    expect(update_domain_routes.logger).to receive(:info).with(/Успешно обработана группа/)
    update_domain_routes.call(group_name, default_interface)
  end
end
