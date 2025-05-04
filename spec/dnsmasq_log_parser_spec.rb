require 'spec_helper'

RSpec.describe DnsmasqLogParser do
  describe '#parse_lines' do
    subject(:parse_lines) { described_class.new.parse_lines(log_lines) }

    let(:log_lines) do
      <<~LOGS.strip
        May  4 12:10:43 dnsmasq[139144]: query[A] time.g.aaplimg.com from 192.168.0.73
        May  4 12:10:43 dnsmasq[139144]: forwarded time.g.aaplimg.com to 8.8.8.8
        May  4 12:10:43 dnsmasq[139144]: forwarded time.g.aaplimg.com to 8.8.4.4
        May  4 12:10:43 dnsmasq[139144]: forwarded time.g.aaplimg.com to 1.1.1.1
        May  4 12:10:43 dnsmasq[139144]: forwarded time.g.aaplimg.com to 1.0.0.1
        May  4 12:10:43 dnsmasq[139144]: reply time.g.aaplimg.com is 17.253.38.125
        May  4 12:10:43 dnsmasq[139144]: reply time.g.aaplimg.com is 17.253.38.253
        May  4 12:10:43 dnsmasq[139144]: reply time.g.aaplimg.com is 17.253.14.253
        May  4 11:59:24 dnsmasq[139144]: query[HTTPS] amp-api-edge-cdn-lb.itunes-apple.com.akadns.net from 192.168.0.73
        May  4 11:59:24 dnsmasq[139144]: cached amp-api-edge-cdn-lb.itunes-apple.com.akadns.net is <CNAME>
        May  4 11:59:24 dnsmasq[139144]: forwarded amp-api-edge-cdn-lb.itunes-apple.com.akadns.net to 1.1.1.1
        May  4 11:59:24 dnsmasq[139144]: query[A] amp-api-edge-cdn-lb.itunes-apple.com.akadns.net from 192.168.0.73
        May  4 11:59:24 dnsmasq[139144]: cached amp-api-edge-cdn-lb.itunes-apple.com.akadns.net is <CNAME>
        May  4 11:59:24 dnsmasq[139144]: cached h3.apis.apple.map.fastly.net is 151.101.3.6
        May  4 11:59:24 dnsmasq[139144]: cached h3.apis.apple.map.fastly.net is 151.101.131.6
        May  4 11:59:24 dnsmasq[139144]: cached h3.apis.apple.map.fastly.net is 151.101.195.6
        May  4 11:59:24 dnsmasq[139144]: cached h3.apis.apple.map.fastly.net is 151.101.67.6
        May  4 11:59:24 dnsmasq[139144]: reply amp-api-edge-cdn-lb.itunes-apple.com.akadns.net is <CNAME>
        May  4 11:59:24 dnsmasq[139144]: reply h3.apis.apple.map.fastly.net is <HTTPS>
      LOGS
    end

    it 'parses multiple valid log lines correctly' do
      expect(parse_lines).to eq(
        [
          {
            query: {
              type: :query,
              query_type: "A",
              domain: "time.g.aaplimg.com",
              client_ip: "192.168.0.73",
              timestamp: Time.parse("2025-05-04 12:10:43 +0300")
            },
            reply: [
              {
                type: :reply,
                domain: "time.g.aaplimg.com",
                ip: "17.253.38.125",
                timestamp: Time.parse("2025-05-04 12:10:43 +0300"),
                cached: false
              },
              {
                type: :reply,
                domain: "time.g.aaplimg.com",
                ip: "17.253.38.253",
                timestamp: Time.parse("2025-05-04 12:10:43 +0300"),
                cached: false
              },
              {
                type: :reply,
                domain: "time.g.aaplimg.com",
                ip: "17.253.14.253",
                timestamp: Time.parse("2025-05-04 12:10:43 +0300"),
                cached: false
              }
            ]
          },
          {
            query: {
              type: :query,
              query_type: "HTTPS",
              domain: "amp-api-edge-cdn-lb.itunes-apple.com.akadns.net",
              client_ip: "192.168.0.73",
              timestamp: Time.parse("2025-05-04 11:59:24 +0300")
            },
            reply: []
          },
          {
            query: {
              type: :query,
              query_type: "A",
              domain: "amp-api-edge-cdn-lb.itunes-apple.com.akadns.net",
              client_ip: "192.168.0.73",
              timestamp: Time.parse("2025-05-04 11:59:24 +0300")
            },
            reply: [
              {
                type: :reply,
                domain: "h3.apis.apple.map.fastly.net",
                ip: "151.101.3.6",
                timestamp: Time.parse("2025-05-04 11:59:24 +0300"),
                cached: true
              },
              {
                type: :reply,
                domain: "h3.apis.apple.map.fastly.net",
                ip: "151.101.131.6",
                timestamp: Time.parse("2025-05-04 11:59:24 +0300"),
                cached: true
              },
              {
                type: :reply,
                domain: "h3.apis.apple.map.fastly.net",
                ip: "151.101.195.6",
                timestamp: Time.parse("2025-05-04 11:59:24 +0300"),
                cached: true
              },
              {
                type: :reply,
                domain: "h3.apis.apple.map.fastly.net",
                ip: "151.101.67.6",
                timestamp: Time.parse("2025-05-04 11:59:24 +0300"),
                cached: true
              }
            ]
          }
        ]
      )
    end

    # it 'handles mixed valid and invalid lines' do
    #   results = described_class.parse_lines(mixed_log_lines)
    #
    #   expect(results.size).to eq(3) # Only valid dnsmasq lines should be parsed
    #
    #   # Verify the valid lines were parsed correctly
    #   expect(results[0][:type]).to eq('query')
    #   expect(results[1][:type]).to eq('reply')
    #   expect(results[2][:type]).to eq('query')
    # end

    it 'returns empty array for empty input' do
      expect(described_class.new.parse_lines('')).to be_empty
    end

    it 'returns empty array for nil input' do
      expect(described_class.new.parse_lines(nil)).to be_empty
    end

    # it 'returns empty array for input with only invalid lines' do
    #   results = described_class.parse_lines("Invalid line 1\nInvalid line 2")
    #   expect(results).to be_empty
    # end
    #
    # it 'handles log rotation by resetting position' do
    #   # Simulate log rotation by providing a shorter log after a longer one
    #   first_log = <<~LOGS
    #     Mar 21 10:15:23 dnsmasq[1234]: query[A] example.com from 192.168.1.100
    #     Mar 21 10:15:24 dnsmasq[1234]: reply example.com is 93.184.216.34
    #   LOGS
    #
    #   rotated_log = <<~LOGS
    #     Mar 21 10:15:25 dnsmasq[1234]: query[A] new-example.com from 192.168.1.100
    #   LOGS
    #
    #   # First parse should get both lines
    #   first_results = described_class.parse_lines(first_log)
    #   expect(first_results.size).to eq(2)
    #
    #   # Second parse should get the new line
    #   second_results = described_class.parse_lines(rotated_log)
    #   expect(second_results.size).to eq(1)
    #   expect(second_results[0][:domain]).to eq('new-example.com')
    # end
  end
end
