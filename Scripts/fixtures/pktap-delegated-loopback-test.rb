#!/usr/bin/env ruby
require 'minitest/autorun'
require_relative 'pktap-delegated-loopback'

class DelegatedLoopbackTrialTest < Minitest::Test
  def test_outbound_effective_pid_and_inbound_receiver_are_separate
    trial = DelegatedLoopbackTrial.new
    trial.instance_variable_set(:@port, 5001)
    trial.instance_variable_set(:@target_pid, 456)
    buffers = trial.instance_variable_get(:@buffers)
    4.times do
      buffers[:observer_stdout] << "(proc 999, eproc 456, out) IP 127.0.0.1.5000 > 127.0.0.1.5001: UDP, length 17\n"
      buffers[:observer_stdout] << "(proc #{Process.pid}, in) IP 127.0.0.1.5000 > 127.0.0.1.5001: UDP, length 17\n"
    end
    buffers[:observer_stdout] << "\n"
    buffers[:sender_stdout] = JSON.generate(kind: 'synthetic-delegated-sender', pid: 999, sent: 4)
    buffers[:observer_stderr] = [
      "tcpdump: verbose output suppressed, use -v[v]... for full protocol decode\n",
      "tcpdump: data link type PKTAP\n",
      "listening on pktap,lo0, link-type PKTAP (Apple DLT_PKTAP), snapshot length 256 bytes\n",
      "8 packets captured\n", "8 packets received by filter\n", "0 packets dropped by kernel\n"
    ].join
    received = Array.new(4, 'synthetic-control')
    receiver = Object.new
    receiver.define_singleton_method(:recv_nonblock) { |_, exception:| received.shift || :wait_readable }
    trial.instance_variable_set(:@receiver, receiver)
    trial.result.merge!(observer_ready: true, full_window: true, observer_exit: 0, sender_exit: 0)
    trial.send(:ingest_packets)
    capture_io { trial.send(:finish) }

    assert_equal 4, trial.result[:delegated_out]
    assert_equal 4, trial.result[:receiver_in]
    assert_equal 0, trial.result[:other_packet_lines]
    assert_equal 0, trial.result[:unparsed_lines]
    assert_equal 1, trial.result[:blank_lines]
    assert_equal false, trial.result[:product_pass]
    assert_equal 'synthetic-delegation-observed', trial.result[:outcome]
    assert_equal 0, trial.result[:unknown_stderr_lines]
    refute_includes trial.result.to_s, '127.0.0.1'
  end

  def test_ambiguous_metadata_does_not_count_as_delegated
    trial = DelegatedLoopbackTrial.new
    trial.instance_variable_set(:@port, 5001)
    buffers = trial.instance_variable_get(:@buffers)
    buffers[:observer_stdout] << "(proc 999, eproc 456, eproc 456, out) IP 127.0.0.1.5000 > 127.0.0.1.5001: UDP, length 17\n"
    trial.send(:ingest_packets)

    assert_equal 1, trial.instance_variable_get(:@unparsed_lines)
    assert_empty trial.instance_variable_get(:@observations)
  end
end
