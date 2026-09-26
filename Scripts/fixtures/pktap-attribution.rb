# Strict reducer for tcpdump -nn -q -t -k PD. Never retains packet text.
module PktapAttribution
  def self.reduce(text, pids:, ports:, receiver_pid:)
    counts = {parsed_packets: 0, outbound: [0, 0], inbound: [0, 0],
              unknown_attribution: 0, unexpected_flow: 0, unparsed_lines: 0,
              unparsed_categories: {blank: 0, packet_like: 0, other: 0},
              unterminated_unparsed_lines: 0}
    text.each_line do |line|
      # Complete lines only; a truncated final record must not become evidence.
      m = /\A\(([^\r\n()]*)\) IP 127\.0\.0\.1\.(\d+) > 127\.0\.0\.1\.(\d+): UDP, length 17\n\z/.match(line)
      unless m && [m[2], m[3]].all? { |v| (1..65_535).cover?(v.to_i) }
        counts[:unparsed_lines] += 1
        # Categories describe shape only, never validity or harmlessness.
        category = if /\A[ \t\r]*\n\z/.match?(line)
                     :blank
                   elsif /\A[ \t]*(?:\(|IP6?\b|\[\|)/.match?(line)
                     :packet_like
                   else
                     :other
                   end
        counts[:unparsed_categories][category] += 1
        counts[:unterminated_unparsed_lines] += 1 unless line.end_with?("\n")
        next
      end
      fields = m[1].split(', ', -1)
      procs = fields.grep(/\Aproc -?\d+\z/)
      directions = fields & ['in', 'out']
      valid = fields.all? { |f| /\A(?:e?proc -?\d+|in|out)\z/.match?(f) } &&
              procs.length == 1 && directions.length == 1 && fields.uniq == fields &&
              fields.grep(/\Aeproc /).length <= 1
      unless valid
        counts[:unknown_attribution] += 1
        next
      end
      counts[:parsed_packets] += 1
      index = ports.first(2).index(m[3].to_i)
      unless index
        counts[:unexpected_flow] += 1
        next
      end
      pid = procs.first.delete_prefix('proc ').to_i
      direction = directions.first
      expected = direction == 'out' ? pids.fetch(index) : receiver_pid
      if pid <= 0 || pid != expected
        counts[:unknown_attribution] += 1
      else
        counts[direction == 'out' ? :outbound : :inbound][index] += 1
      end
    end
    # Observations are not deduplicated datagrams and never qualify the product.
    counts
  end
end
