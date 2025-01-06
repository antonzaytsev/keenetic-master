class KeeneticMaster
  class DeleteRoute < AaMutateRouteRequest
    def call(host: nil, network: nil, mask: nil)
      route = {
        "no" => true,
      }

      process_host(route, host:, network:, mask:)

      response = Client.new.post_rci(build_body(route))
      Failure(response) if response.code != 200

      Success()
    end
  end
end
