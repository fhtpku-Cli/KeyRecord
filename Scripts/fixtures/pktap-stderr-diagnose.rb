#!/usr/bin/env ruby
require 'json'
require 'socket'
require 'timeout'

USAGE = <<~TEXT
  Usage: ruby Scripts/fixtures/pktap-stderr-diagnose.rb --check|--run
  --check validates the local tool without sudo or capture.
  --run requires separate owner approval: 8 seconds of filtered pktap,lo0 capture.
  Only tcpdump is elevated. Packet text is discarded; stderr stays in memory.
  Afterward, typing REVIEW may show stderr only in the local terminal.
TEXT

unless [%w[--help], %w[--check], %w[--run]].include?(ARGV)
  warn USAGE
  exit 1
end
if ARGV == ['--help']
  puts USAGE
  exit 0
end

def check_environment
  raise 'macOS required' unless RUBY_PLATFORM.include?('darwin')
  raise 'run as a normal user' if Process.uid == 0 || Process.euid == 0
  raise 'system tcpdump missing' unless File.executable?('/usr/sbin/tcpdump')
  raise 'system sudo missing' unless File.executable?('/usr/bin/sudo')
end

begin
  check_environment
rescue StandardError => error
  warn error.message
  exit 1
end
if ARGV == ['--check']
  puts JSON.generate(kind: 'loopback-stderr-diagnostic', outcome: 'prepared', product_pass: false)
  exit 0
end

clock = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
result = {kind: 'loopback-stderr-diagnostic', product_pass: false,
          outcome: 'inconclusive', interface: 'pktap,lo0', capture_limit_seconds: 8,
          observer_ready: false, control_sent: 0, control_received: 0}
stderr_text = +''
stdout_bytes = 0
stdout_lines = 0
readers = []
observer = nil
receiver = sender = nil

begin
  receiver = UDPSocket.new
  sender = UDPSocket.new
  receiver.bind('127.0.0.1', 0)
  port = receiver.addr[1]
  filter = "ip and udp and src host 127.0.0.1 and dst host 127.0.0.1 and dst port #{port}"

  puts 'Administrator authentication is needed only for the system tcpdump process.'
  raise 'authentication failed' unless system('/usr/bin/sudo', '-v')
  out_r, out_w = IO.pipe
  err_r, err_w = IO.pipe
  readers = [out_r, err_r]
  observer = Process.spawn('/usr/bin/sudo', '-n', '/usr/sbin/tcpdump', '-nn', '-q', '-l', '-t',
                           '-i', 'pktap,lo0', '-k', 'PD', '-s', '256', '-c', '64', filter,
                           out: out_w, err: err_w, pgroup: true)
  out_w.close
  err_w.close

  drain = lambda do |timeout|
    selected = IO.select(readers, nil, nil, timeout)
    next unless selected
    selected[0].each do |io|
      chunk = io.read_nonblock(4096, exception: false)
      if chunk.nil?
        readers.delete(io)
      elsif chunk != :wait_readable
        if io == out_r
          stdout_bytes += chunk.bytesize
          stdout_lines += chunk.count("\n")
          raise 'packet output limit exceeded' if stdout_bytes > 65_536
        else
          raise 'diagnostic output limit exceeded' if stderr_text.bytesize + chunk.bytesize > 8192
          stderr_text << chunk
        end
      end
    end
  end

  started = clock.call
  ready_at = nil
  loop do
    drain.call(0.2)
    if !ready_at && /(?:\A|\n)tcpdump: listening on pktap,lo0, link-type [^\r\n]+, snapshot length 256 bytes\n/.match?(stderr_text)
      ready_at = clock.call
      result[:observer_ready] = true
      4.times { sender.send('synthetic-control', 0, '127.0.0.1', port) }
      result[:control_sent] = 4
    end
    break if readers.empty? || (ready_at && clock.call - ready_at >= 8)
    raise 'observer readiness timeout' if !ready_at && clock.call - started >= 5
  end
  result[:capture_seconds] = ready_at ? (clock.call - ready_at).round(2) : 0

  Process.kill('INT', -observer) rescue Errno::ESRCH
  status = Timeout.timeout(4) do
    drain.call(0.2) until readers.empty?
    Process.waitpid2(observer).last
  end
  observer = nil
  result[:observer_exit] = status.exitstatus
  loop do
    data = receiver.recv_nonblock(64, exception: false)
    break if data == :wait_readable
    raise 'unexpected control payload' unless data == 'synthetic-control'
    result[:control_received] += 1
  end
  result[:outcome] = 'diagnostic-complete' if result[:observer_ready] &&
                                             result[:observer_exit] == 0 &&
                                             result[:control_received] == 4 &&
                                             result[:capture_seconds] >= 7.5
rescue StandardError => error
  result[:error_type] = error.class.name
ensure
  if observer
    Process.kill('TERM', -observer) rescue Errno::ESRCH
    begin
      Timeout.timeout(2) { Process.waitpid(observer) }
    rescue Timeout::Error
      Process.kill('KILL', -observer) rescue Errno::ESRCH
      Process.waitpid(observer) rescue Errno::ECHILD
    rescue Errno::ECHILD
      nil
    end
  end
  [out_w, err_w].compact.each { |io| io.close unless io.closed? }
  readers.each { |io| io.close unless io.closed? }
  receiver&.close
  sender&.close
  result[:stdout_bytes] = stdout_bytes
  result[:stdout_lines] = stdout_lines
  result[:stderr_lines] = stderr_text.lines.count
  result[:captured_count] = stderr_text[/^(\d+) packets? captured$/, 1]&.to_i
  result[:kernel_drops] = stderr_text[/^(\d+) packets? dropped by kernel$/, 1]&.to_i
  puts JSON.pretty_generate(result)
  if !stderr_text.empty? && STDIN.tty?
    puts 'Optional local review: stderr may contain hostnames or paths. Terminal scrollback may retain it.'
    print 'Type REVIEW to display stderr here, or press Return to skip: '
    if STDIN.gets == "REVIEW\n"
      stderr_text.lines.each { |line| puts line.dump }
    end
  end
end
exit(result[:outcome] == 'diagnostic-complete' ? 0 : 2)
