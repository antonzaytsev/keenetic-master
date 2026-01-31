class KeeneticMaster
  class CorrectInterface < BaseClass
    def call(interface)
      return interface if existing_interfaces.failure?

      existing_interfaces_list = existing_interfaces.value!
      return interface if existing_interfaces_list.key?(interface)

      existing_interface = existing_interfaces_list.values.detect { |data| data['description'] == interface }
      return interface if existing_interface.nil?

      existing_interface['id']
    end

    private

    def existing_interfaces
      @existing_interfaces ||= KeeneticMaster.interface
    end
  end
end
