#!/usr/bin/env ruby
require 'minitest/autorun'
require_relative 'product-network-observe'

class ProductNetworkObserveTest < Minitest::Test
  def test_counts_control_and_product_without_retaining_packet_text
    counts = ProductPacketCounts.new(123)
    counts.control_port = 4321
    4.times do
      counts.ingest("(proc 123, out) IP 127.0.0.1.5000 > 127.0.0.1.4321: UDP, length 17\n")
      counts.ingest("(proc 123, in) IP 127.0.0.1.5000 > 127.0.0.1.4321: UDP, length 17\n")
    end
    counts.ingest("(proc 456, out) IP6 ::1.9000 > ::1.9001: Flags [S]\n")
    result = counts.summary(456)
    assert_equal({out: 4, in: 4}, result[:control])
    assert_equal({out: 1, in: 0, unknown_direction: 0}, result[:product])
    assert_equal({'ipv4' => 8, 'ipv6' => 1}, result[:families])
    refute_includes result.to_s, '127.0.0.1'
  end

  def test_missing_or_ambiguous_attribution_is_counted
    counts = ProductPacketCounts.new(123)
    counts.ingest("(out) IP 1.1.1.1.10 > 2.2.2.2.20: Flags [S]\n")
    counts.ingest("(proc 456, in, out) IP 1.1.1.1.10 > 2.2.2.2.20: Flags [S]\n")
    counts.ingest("(proc 456, unknown, out) IP 1.1.1.1.10 > 2.2.2.2.20: Flags [S]\n")
    counts.ingest("(proc 456, out) ARP, Request who-has 1.1.1.1\n")
    counts.ingest("\n")
    counts.ingest("garbled packet\n")
    result = counts.summary(456)
    assert_equal 2, result[:unattributed]
    assert_equal 1, result[:unknown_direction]
    assert_equal 1, result[:product][:out]
    assert_equal 1, result[:blank_lines]
    assert_equal 1, result[:unparsed_lines]
  end

  def test_blank_observer_diagnostic_is_separate_from_unknown_diagnostic
    blank = valid_observation
    blank.send(:ingest_stderr, "\n")
    blank.send(:ingest_stderr, " \t\r\n")
    capture_io { blank.send(:finish_receipt) }
    assert_equal 2, blank.receipt[:stderr_blank_lines]
    assert_equal 'bounded-no-attributed-outbound-observed', blank.receipt[:outcome]

    unknown = valid_observation
    unknown.send(:ingest_stderr, "tcpdump: unexpected diagnostic\n")
    capture_io { unknown.send(:finish_receipt) }
    assert_equal 1, unknown.receipt[:stderr_other_lines]
    assert_equal 'invalid', unknown.receipt[:outcome]
  end

  private

  def valid_observation
    observation = ProductNetworkObservation.new(app: '/unused', seconds: 75)
    counts = observation.instance_variable_get(:@counts)
    counts.control_port = 4321
    4.times do
      counts.ingest("(proc #{Process.pid}, out) IP 127.0.0.1.5000 > 127.0.0.1.4321: UDP, length 17\n")
      counts.ingest("(proc #{Process.pid}, in) IP 127.0.0.1.5000 > 127.0.0.1.4321: UDP, length 17\n")
    end
    observation.instance_variable_set(:@product_pid, 456)
    observation.receipt.merge!(observer_ready: true, full_window: true, idle_timer_elapsed: true,
      observer_exit: 0, kernel_drops: 0, captured_count: 8, control_sent: 4,
      control_received: 4, product_exited: true, product_exit: 0,
      product_aggregate_delta: 1, unterminated_output_bytes: 0, sleep_interrupted: false)
    observation
  end
end
