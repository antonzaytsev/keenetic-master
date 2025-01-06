class KeeneticMaster
  class DeleteRoutes < AaMutateRouteRequest
    def call(routes)
      return Success(empty: true) if routes.empty?

      routes.each do |route|
        route["no"] = true

        process_host(route, host: route['host'], network: route['host'], mask: route['host'])
      end

      response = Client.new.post_rci(build_body_routes(routes))
      Failure(response) if response.code != 200

      Success()
    end
  end
end
