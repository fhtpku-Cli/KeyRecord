#!/usr/bin/env ruby
require 'json'
require 'open3'
require 'tempfile'
require_relative '../product-network-observe'

if ARGV == ['--help']
  puts 'Usage: ruby Scripts/fixtures/pktap-effective-metadata-offline.rb'
  puts 'Generates one synthetic PCAPNG packet and checks tcpdump -r -k PD output; no sudo or network.'
  exit 0
end
abort 'No arguments are accepted.' unless ARGV.empty?
abort 'macOS tcpdump required' unless RUBY_PLATFORM.include?('darwin') && File.executable?('/usr/sbin/tcpdump')

module SyntheticProcessPcapng
  SENDER_PID = 20_001
  EFFECTIVE_PID = 20_002

  def self.option(code, value)
    [code, value.bytesize].pack('vv') + value + ("\0" * ((-value.bytesize) % 4))
  end

  def self.block(type, body)
    length = body.bytesize + 12
    [type, length].pack('VV') + body + [length].pack('V')
  end

  def self.packet
    ethernet = ("\0" * 12) + [0x0800].pack('n')
    payload = 'synthetic-control'
    ipv4 = [0x45, 0, 20 + 8 + payload.bytesize, 0, 0, 64, 17, 0].pack('CCnnnCCn') +
           [127, 0, 0, 1, 127, 0, 0, 1].pack('C*')
    udp = [5000, 5001, 8 + payload.bytesize, 0].pack('nnnn')
    ethernet + ipv4 + udp + payload
  end

  def self.bytes
    section = block(0x0a0d0d0a, [0x1a2b3c4d, 1, 0, 0xffffffffffffffff].pack('VvvQ<'))
    interface = block(1, [1, 0, 256].pack('vvV') + option(2, 'lo0') + option(0, ''))
    sender = block(0x80000001, [SENDER_PID].pack('V') + option(2, 'synthetic-sender') + option(0, ''))
    effective = block(0x80000001, [EFFECTIVE_PID].pack('V') + option(2, 'synthetic-owner') + option(0, ''))
    data = packet
    options = option(2, [2].pack('V')) + option(0x8001, [0].pack('V')) +
              option(0x8003, [1].pack('V')) + option(0, '')
    enhanced = block(6, [0, 0, 0, data.bytesize, data.bytesize].pack('V5') +
                        data + ("\0" * ((-data.bytesize) % 4)) + options)
    section + interface + sender + effective + enhanced
  end
end

result = {kind: 'synthetic-effective-process-metadata', product_pass: false,
          outcome: 'inconclusive', network_capture: false, sudo_used: false}
begin
  Tempfile.create(['pktap-effective-', '.pcapng']) do |file|
    file.write(SyntheticProcessPcapng.bytes)
    file.flush
    stdout, stderr, status = Open3.capture3('/usr/sbin/tcpdump', '-nn', '-q', '-t',
                                            '-k', 'PD', '-r', file.path)
    result[:tcpdump_exit] = status.exitstatus
    result[:stderr_lines] = stderr.lines.count
    result[:expected_metadata] = stdout.start_with?(
      "(proc #{SyntheticProcessPcapng::SENDER_PID}, eproc #{SyntheticProcessPcapng::EFFECTIVE_PID}, out) "
    )
    counts = ProductPacketCounts.new(-1)
    stdout.each_line { |line| counts.ingest(line) }
    summary = counts.summary(SyntheticProcessPcapng::EFFECTIVE_PID)
    result[:parsed_packets] = summary[:packets] - summary[:unattributed]
    result[:unparsed_lines] = summary[:unparsed_lines]
    result[:effective_product_from_other_proc] = summary[:effective_product_from_other_proc]
    if status.success? && result[:expected_metadata] && summary[:packets] == 1 && summary[:unattributed] == 0 &&
       summary[:unparsed_lines] == 0 && summary[:effective_product_from_other_proc][:out] == 1
      result[:outcome] = 'offline-printer-and-reducer-verified'
    end
  end
rescue StandardError => error
  result[:error_type] = error.class.name
ensure
  puts JSON.pretty_generate(result)
end
exit(result[:outcome] == 'offline-printer-and-reducer-verified' ? 0 : 2)
