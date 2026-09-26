#!/usr/bin/env ruby
# Owner-approved synthetic loopback capture only. No product/zero-egress pass.
require 'socket'
require 'rbconfig'
require 'timeout'
require 'json'
require_relative 'pktap-attribution'
if ARGV.empty? || ARGV == ['--help']
  puts 'Usage: ruby Scripts/fixtures/pktap-loopback-pilot.rb --run'
  puts '20-second synthetic IPv4 loopback PKTAP pilot; no external traffic or raw capture file.'
  puts 'Never invokes sudo. Prints metadata-only JSON; unparsed attribution is inconclusive.'
  exit 0
end
abort 'Only --run is accepted; arbitrary interfaces and targets are unsupported.' unless ARGV == ['--run']
abort 'macOS tcpdump required' unless RUBY_PLATFORM.include?('darwin') && File.executable?('/usr/sbin/tcpdump')
children = []
streams = []
sockets = []
result = {kind: 'synthetic-pktap-pilot', product_pass: false, outcome: 'inconclusive', packets_sent: 0}
clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
begin
  # Reserve all destination ports throughout capture, including the excluded decoy.
  3.times do
    s = UDPSocket.new
    s.bind('127.0.0.1', 0)
    sockets << s
  end
  ports = sockets.map { |s| s.addr[1] }
  controls = ports.each_with_index.map do |port, index|
    ir, iw = IO.pipe
    or_, ow = IO.pipe
    streams.concat([ir, iw, or_, ow])
    code = <<~'CODE'
      require 'socket'
      STDOUT.sync=true
      s=UDPSocket.new
      puts 'ready'
      exit unless STDIN.gets == "send\n"
      4.times { s.send('synthetic-control', 0, '127.0.0.1', ARGV.fetch(0).to_i) }
      s.close if ARGV.fetch(1)=='short'
      puts 'sent'
      STDIN.gets
      s.close unless s.closed?
    CODE
    pid = Process.spawn(RbConfig.ruby, '-e', code, port.to_s, index == 1 ? 'short' : 'held', in: ir, out: ow)
    children << pid
    ir.close; ow.close
    raise 'control readiness failed' unless Timeout.timeout(3) { or_.gets } == "ready\n"
    [pid, iw, or_]
  end
  result[:control_pids] = controls.map(&:first)
  result[:ports] = ports
  filter = "ip and udp and src host 127.0.0.1 and dst host 127.0.0.1 and (dst port #{ports[0]} or dst port #{ports[1]})"
  out_r, out_w = IO.pipe
  err_r, err_w = IO.pipe
  streams.concat([out_r, out_w, err_r, err_w])
  observer = Process.spawn('/usr/sbin/tcpdump', '-nn', '-q', '-l', '-t', '-i', 'pktap,lo0',
                           '-k', 'PD', '-s', '256', '-c', '512', filter, out: out_w, err: err_w)
  children << observer
  out_w.close; err_w.close
  stdout = +''; stderr = +''
  started = clock.call
  ready_at = nil
  readers = [out_r, err_r]
  loop do
    break if readers.empty?
    break if ready_at && clock.call - ready_at >= 20
    raise 'observer readiness timeout' if !ready_at && clock.call - started > 5
    selected = IO.select(readers, nil, nil, 0.2)
    if selected
      selected[0].each do |io|
        chunk = io.read_nonblock(4096, exception: false)
        if chunk.nil?
          readers.delete(io)
        elsif chunk != :wait_readable
          (io == out_r ? stdout : stderr) << chunk
          raise 'observer output limit exceeded' if stdout.bytesize + stderr.bytesize > 65_536
        end
      end
    end
    if !ready_at && stderr.include?('listening on')
      ready_at = clock.call
      controls.each { |_, input, _| input.puts 'send' }
      controls.each { |_, _, output| raise 'send failed' unless Timeout.timeout(2) { output.gets } == "sent\n" }
      result[:packets_sent] = 12
    end
  end
  # Stop/reap this observer only. Drain its bounded final statistics.
  Process.kill('INT', observer) rescue Errno::ESRCH
  status = Timeout.timeout(3) { Process.wait2(observer).last }
  children.delete(observer)
  [out_r, err_r].each do |io|
    remaining = io.read(65_537)
    (io == out_r ? stdout : stderr) << remaining.to_s
  end
  raise 'observer output limit exceeded' if stdout.bytesize + stderr.bytesize > 65_536
  result[:observer_exit] = status.exitstatus
  result[:observer_signal] = status.termsig
  result[:observer_ready] = !ready_at.nil?
  result[:capture_seconds] = ready_at ? (clock.call - ready_at).round(2) : 0
  result[:permission_denied] = stderr.match?(/permission denied|operation not permitted/i)
  result[:outcome] = result[:permission_denied] ? 'blocked-permission' : 'inconclusive-attribution-not-validated'
  result[:captured_count] = stderr[/^(\d+) packets? captured$/, 1]&.to_i
  result[:kernel_drop_count] = stderr[/^(\d+) packets? dropped by kernel$/, 1]&.to_i
  result[:output_lines] = stdout.lines.count
  # Do not serialize tcpdump text, payloads, names or UUIDs. This pilot has no PASS path.
  result[:attribution] = PktapAttribution.reduce(stdout, pids: controls.map(&:first), ports: ports, receiver_pid: Process.pid)
  result[:received_control_packets] = sockets.map do |s|
    count = 0
    loop do
      data = s.recv_nonblock(256, exception: false)
      break if data == :wait_readable
      raise 'unexpected control payload' unless data == 'synthetic-control'
      count += 1
    end
    count
  end
rescue StandardError => e
  result[:outcome] = 'invalid'
  result[:error_type] = e.class.name
ensure
  streams.each { |io| io.close unless io.closed? }
  children.each do |pid|
    begin
      Process.kill('TERM', pid)
      Timeout.timeout(3) { Process.wait(pid) }
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    rescue Timeout::Error
      Process.kill('KILL', pid)
      Process.wait(pid)
    end
  end
  sockets.each(&:close)
  puts JSON.pretty_generate(result)
end
exit(result[:outcome] == 'blocked-permission' ? 2 : 1)
