require 'minitest/autorun'
require 'json'
require_relative 'pktap-attribution'
class PktapAttributionTest < Minitest::Test
  def parse(text)
    PktapAttribution.reduce(text, pids: [101, 102, 103], ports: [8001, 8002, 8003], receiver_pid: 200)
  end
  def packet(metadata = 'proc 101, out', source = 9000, dest = 8001)
    "(#{metadata}) IP 127.0.0.1.#{source} > 127.0.0.1.#{dest}: UDP, length 17\n"
  end
  def test_both_controls_and_directions
    r = parse(packet + packet('proc 102, out', 9001, 8002) + packet('proc 200, in'))
    assert_equal [1, 1], r[:outbound]
    assert_equal [1, 0], r[:inbound]
  end
  def test_pid_in_source_port_is_not_attribution
    r = parse(packet('proc 999, out', 101))
    assert_equal [0, 0], r[:outbound]
    assert_equal 1, r[:unknown_attribution]
  end
  def test_effective_pid_is_not_sender_pid
    assert_equal 1, parse(packet('proc 999, eproc 101, out'))[:unknown_attribution]
  end
  def test_missing_unknown_duplicate_or_ambiguous_fields
    ['out', 'proc -1, out', 'proc 101', 'proc 101, in, out',
     'proc 101, proc 101, out', 'proc 101, eproc 1, eproc 2, out',
     'proc ruby:101, out', 'proc 999, uuid 101, out'].each do |fields|
      assert_equal 1, parse(packet(fields))[:unknown_attribution], fields
    end
  end
  def test_decoy_flow_is_not_counted
    r = parse(packet('proc 103, out', 9002, 8003))
    assert_equal 1, r[:unexpected_flow]
    assert_equal [0, 0], r[:outbound]
  end
  def test_truncation_and_foreign_output_are_not_ignored
    [packet.chomp, packet.sub('127.0.0.1', '192.0.2.1'), '[|ip]' + "\n",
     "warning 101\n", packet('proc 101, out', 70000)].each do |line|
      assert_equal 1, parse(line)[:unparsed_lines]
    end
  end
  def test_duplicate_observations_are_not_silently_deduplicated
    assert_equal [2, 0], parse(packet + packet)[:outbound]
  end
  def test_empty_output_is_no_evidence
    assert_equal [0, 0], parse('')[:outbound]
    refute parse('').key?(:product_pass)
  end
  def test_unparsed_categories_account_for_every_unparsed_line
    text = "\n \t\r\n" + packet.chomp + "\n" + "[|ip]\nIP6 malformed\nwarning private-marker\n"
    r = parse(text)
    assert_equal 1, r[:parsed_packets]
    assert_equal({blank: 2, packet_like: 2, other: 1}, r[:unparsed_categories])
    assert_equal 5, r[:unparsed_lines]
    assert_equal r[:unparsed_lines], r[:unparsed_categories].values.sum
    assert_equal 0, r[:unterminated_unparsed_lines]
    refute_includes JSON.generate(r), 'private-marker'
  end
  def test_truncated_records_remain_unparsed_even_when_packet_like
    r = parse(packet.chomp)
    assert_equal 1, r[:unparsed_categories][:packet_like]
    assert_equal 1, r[:unterminated_unparsed_lines]
    assert_equal 0, r[:parsed_packets]
    r = parse(' ')
    assert_equal 0, r[:unparsed_categories][:blank]
    assert_equal 1, r[:unparsed_categories][:other]
    assert_equal 1, r[:unterminated_unparsed_lines]
  end
  def test_blank_line_does_not_disappear_or_become_pass
    r = parse("\n")
    assert_equal 1, r[:unparsed_lines]
    assert_equal 1, r[:unparsed_categories][:blank]
    assert_equal 0, r[:parsed_packets]
    refute r.key?(:product_pass)
    refute r.key?(:outcome)
  end

end
