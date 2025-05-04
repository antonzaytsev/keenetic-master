class DnsmasqLogParser
  def parse_lines(lines)
    return [] if lines.nil?

    groups = []

    current_group = nil
    lines.each_line do |line|
      parsed = parse_line(line)
      next if parsed.nil?

      case parsed[:type]
      when :query
        groups << current_group if current_group
        current_group = {query:nil, reply: []}
        current_group[parsed[:type]] = parsed
      when :reply
        if current_group
          current_group[parsed[:type]] << parsed
        end
      end
    end

    groups << current_group if current_group

    groups
  end

  private

  def parse_line(line)
    return unless line.include?('dnsmasq')

    if line.include?('query[')
      parse_query(line)
    elsif line.include?('reply') || line.include?('cached')
      parse_reply(line)
    end
  end

  def parse_query(line)
    # Extract domain and client IP from query
    match = line.match(/query\[([A-Z]+)\] ([^\s]+) from ([0-9.]+)/)
    return if match.nil?

    {
      type: :query,
      query_type: match[1],
      domain: match[2],
      client_ip: match[3],
      timestamp: extract_timestamp(line)
    }
  end

  def parse_reply(line)
    # Extract domain and resolved IP from reply
    match = line.match(/(?:reply|cached) ([^\s]+) is ([0-9.]+)/)
    return if match.nil?

    {
      type: :reply,
      domain: match[1],
      ip: match[2],
      timestamp: extract_timestamp(line),
      cached: line.include?('cached')
    }
  end

  def extract_timestamp(line)
    # Extract timestamp from the beginning of the line
    match = line.match(/^(\w+\s+\d+\s+\d+:\d+:\d+)/)
    return if match.nil?

    Time.parse(match[1])
  end
end
