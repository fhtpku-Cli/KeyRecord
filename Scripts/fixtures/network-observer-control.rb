#!/usr/bin/env ruby
# Synthetic loopback control only; not a KeyRecord or zero-egress qualification.
require 'socket'
require 'rbconfig'
require 'timeout'
require 'tmpdir'
require 'csv'
require 'json'

if ARGV == ['--help'] || ARGV.empty?
  puts 'Usage: ruby Scripts/fixtures/network-observer-control.rb --self-check'
  puts 'Runs two owned synthetic processes and PID-filtered nettop for seven samples.'
  puts 'Sends 1 MiB only to 127.0.0.1; no packet capture or product launch.'
  exit 0
end
abort 'Expected --self-check; arbitrary target PIDs are not supported.' unless ARGV == ['--self-check']
abort 'This self-check requires macOS nettop.' unless RUBY_PLATFORM.include?('darwin') && File.executable?('/usr/bin/nettop')

root = Dir.mktmpdir('keyrecord-network-control-')
File.chmod(0700, root)
children = []
streams = []
receiver = nil
server = nil
begin
  server = TCPServer.new('127.0.0.1', 0)
  receiver = Thread.new do
    socket = server.accept
    count = 0
    begin
      loop { count += socket.readpartial(65_536).bytesize }
    rescue EOFError
      count
    ensure
      socket.close
    end
  end
  sender_code = <<~'CODE'
    require 'socket'
    socket = TCPSocket.new('127.0.0.1', ARGV.fetch(0).to_i)
    STDOUT.sync = true
    puts 'ready'
    STDIN.gets
    32.times { socket.write('x' * 32_768); sleep 0.05 }
    puts 'sent'
    STDIN.gets
    socket.close
  CODE
  spawn_control = lambda do |code, *args|
    input_read, input_write = IO.pipe
    output_read, output_write = IO.pipe
    streams.concat([input_read, input_write, output_read, output_write])
    pid = Process.spawn(RbConfig.ruby, '-e', code, *args, in: input_read, out: output_write)
    children << pid
    input_read.close
    output_write.close
    raise 'control did not become ready' unless Timeout.timeout(5) { output_read.gets } == "ready\n"
    [pid, input_write, output_read]
  end
  sender_pid, sender_in, sender_out = spawn_control.call(sender_code, server.addr[1].to_s)
  idle_pid, idle_in, = spawn_control.call('STDOUT.sync=true;puts "ready";STDIN.gets')
  logs = %w[sender idle].map { |name| File.open(File.join(root, "#{name}.csv"), 'w', 0600) }
  errors = %w[sender idle].map { |name| File.open(File.join(root, "#{name}.stderr"), 'w', 0600) }
  streams.concat(logs + errors)
  monitors = [sender_pid, idle_pid].each_with_index.map do |pid, index|
    child = Process.spawn('/usr/bin/nettop', '-n', '-P', '-x', '-L', '7', '-s', '1',
                          '-p', pid.to_s, '-J', 'bytes_in,bytes_out', out: logs[index], err: errors[index])
    children << child
    child
  end
  sleep 2
  sender_in.puts 'send'
  raise 'sender failed' unless Timeout.timeout(5) { sender_out.gets } == "sent\n"
  statuses = monitors.map do |pid|
    status = Timeout.timeout(15) { Process.wait2(pid).last }
    children.delete(pid)
    status.exitstatus
  end
  sender_in.puts 'close'
  idle_in.puts 'close'
  received = Timeout.timeout(5) { receiver.value }
  [sender_pid, idle_pid].each do |pid|
    status = Timeout.timeout(5) { Process.wait2(pid).last }
    children.delete(pid)
    raise 'control failed' unless status.success?
  end
  (logs + errors).each(&:close)
  raise 'monitor failed' unless statuses == [0, 0]
  raise 'unexpected monitor stderr; inspect retained artifacts' unless %w[sender idle].all? { |n| File.zero?(File.join(root, "#{n}.stderr")) }
  raise 'receiver payload mismatch' unless received == 1_048_576
  # A missing row is unknown, never zero. Accept only this run's exact PID rows.
  values = lambda do |name, pid|
    rows = CSV.read(File.join(root, "#{name}.csv"))
    data = rows.reject { |r| r[0].nil? || r[0].empty? }
    raise 'unexpected process attribution' unless data.all? { |r| r[0].end_with?(".#{pid}") }
    data.map { |r| [Integer(r.fetch(1), 10), Integer(r.fetch(2), 10)] }
  end
  sent_rows = values.call('sender', sender_pid)
  idle_rows = values.call('idle', idle_pid)
  raise 'positive control missed known traffic' unless sent_rows.any? { |r| r[1] >= received }
  raise 'idle control unexpectedly reports traffic' unless idle_rows.all? { |r| r == [0, 0] }
  result = {
    kind: 'synthetic-loopback-observer-control', product_pass: false,
    sender_pid: sender_pid, idle_pid: idle_pid, receiver_bytes: received,
    sender_observed_max_bytes_out: sent_rows.map(&:last).max,
    idle_observation: idle_rows.empty? ? 'no-row-inconclusive' : 'sampled-zero-only',
    samples_requested_per_monitor: 7, monitor_exit_codes: statuses,
    artifacts: root
  }
  File.write(File.join(root, 'result.json'), JSON.pretty_generate(result))
  puts JSON.pretty_generate(result)
ensure
  # Stop only child processes created above that have not already been reaped.
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
  streams.each { |io| io.close unless io.closed? }
  server.close if server && !server.closed?
  receiver.kill if receiver && receiver.alive?
  warn "Synthetic evidence retained: #{root}"
end
