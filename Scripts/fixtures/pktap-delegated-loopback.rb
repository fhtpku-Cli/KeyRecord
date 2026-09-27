#!/usr/bin/env ruby
require 'json'
require 'socket'
require 'timeout'

USAGE = <<~TEXT
  Usage: ruby Scripts/fixtures/pktap-delegated-loopback.rb --check|--run
  --check makes no network or privilege request.
  --run requires separate approval: sudo tcpdump and a sudo synthetic sender.
  The capture is filtered to one ephemeral IPv4 loopback UDP port for eight seconds.
  No KeyRecord App, product store, real packet file, or external address is used.
TEXT

def validate_environment
  raise 'macOS required' unless RUBY_PLATFORM.include?('darwin')
  raise 'normal user required' if Process.uid == 0 || Process.euid == 0
  raise 'system tcpdump missing' unless File.executable?('/usr/sbin/tcpdump')
  raise 'system Ruby missing' unless File.executable?('/usr/bin/ruby')
  raise 'system sudo missing' unless File.executable?('/usr/bin/sudo')
  raise 'sender missing' unless File.file?(File.join(__dir__, 'pktap-delegated-sender.rb'))
end

class DelegatedLoopbackTrial
  attr_reader :result

  def initialize
    @result = {kind: 'synthetic-delegated-loopback', outcome: 'inconclusive',
               product_pass: false, interface: 'pktap,lo0', capture_limit_seconds: 8,
               observer_ready: false, control_sent: 0, control_received: 0}
    @readers = {}
    @buffers = {observer_stdout: +'', observer_stderr: +'', sender_stdout: +'', sender_stderr: +''}
    @observations = []
    @packet_lines = @unparsed_lines = @blank_lines = 0
  end

  def run
    puts 'This approved run would authenticate sudo for system tcpdump and the fixed synthetic sender.'
    raise 'sudo authentication failed' unless system('/usr/bin/sudo', '-v')
    @receiver = UDPSocket.new
    @receiver.bind('127.0.0.1', 0)
    @port = @receiver.addr[1]
    start_target
    start_observer
    started = monotonic
    ready_at = nil
    loop do
      drain_once
      if !ready_at && /(?:\A|\n)(?:tcpdump: )?listening on pktap,lo0, link-type [^\r\n]+, snapshot length 256 bytes\n/.match?(@buffers[:observer_stderr])
        ready_at = monotonic
        @result[:observer_ready] = true
        start_sender
      end
      if ready_at && monotonic - ready_at >= 8
        @result[:full_window] = true
        break
      end
      raise 'observer readiness timeout' if !ready_at && monotonic - started >= 5
      break if @readers.empty?
    end
    @result[:capture_seconds] = ready_at ? (monotonic - ready_at).round(2) : 0
  rescue StandardError => error
    @result[:error_type] = error.class.name
  ensure
    stop_observer
    stop_sender
    drain_remaining
    stop_target
    @readers.each_key { |io| io.close unless io.closed? }
    begin
      finish
    ensure
      @receiver&.close
    end
  end

  private

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def start_target
    input, @target_hold = IO.pipe
    @target_pid = Process.spawn('/usr/bin/ruby', '-e', 'STDIN.read',
                                in: input, out: File::NULL, err: File::NULL)
    input.close
  end

  def start_observer
    filter = "ip and udp and src host 127.0.0.1 and dst host 127.0.0.1 and dst port #{@port}"
    out_r, out_w = IO.pipe
    err_r, err_w = IO.pipe
    @observer_pid = Process.spawn('/usr/bin/sudo', '-n', '/usr/sbin/tcpdump',
                                  '-nn', '-q', '-l', '-t', '-i', 'pktap,lo0',
                                  '-k', 'PD', '-s', '256', '-c', '64', filter,
                                  out: out_w, err: err_w, pgroup: true)
    out_w.close
    err_w.close
    @readers[out_r] = :observer_stdout
    @readers[err_r] = :observer_stderr
  end

  def start_sender
    raise 'delegation target exited' if Process.waitpid2(@target_pid, Process::WNOHANG)
    out_r, out_w = IO.pipe
    err_r, err_w = IO.pipe
    @sender_pid = Process.spawn('/usr/bin/sudo', '-n', '/usr/bin/ruby',
                                File.join(__dir__, 'pktap-delegated-sender.rb'),
                                '--send', @target_pid.to_s, @port.to_s,
                                out: out_w, err: err_w, pgroup: true)
    out_w.close
    err_w.close
    @readers[out_r] = :sender_stdout
    @readers[err_r] = :sender_stderr
  end

  def drain_once(timeout = 0.2)
    selected = IO.select(@readers.keys, nil, nil, timeout)
    return unless selected
    selected[0].each do |io|
      chunk = io.read_nonblock(4096, exception: false)
      if chunk.nil?
        @readers.delete(io)
        io.close
      elsif chunk != :wait_readable
        key = @readers.fetch(io)
        @buffers[key] << chunk
        limit = key == :observer_stderr ? 8192 : key == :observer_stdout ? 8192 : 2048
        raise 'bounded output exceeded' if @buffers[key].bytesize > limit
        ingest_packets if key == :observer_stdout
      end
    end
  end

  def ingest_packets
    while (index = @buffers[:observer_stdout].index("\n"))
      line = @buffers[:observer_stdout].slice!(0..index)
      if /\A[ \t\r]*\n\z/.match?(line)
        @blank_lines += 1
        next
      end
      @packet_lines += 1
      match = /\A\(([^\r\n()]*)\) IP 127\.0\.0\.1\.\d+ > 127\.0\.0\.1\.(\d+): UDP, length 17\n\z/.match(line)
      unless match && match[2].to_i == @port
        @unparsed_lines += 1
        next
      end
      fields = match[1].split(', ', -1)
      proc_fields = fields.grep(/\Aproc \d+\z/)
      effective_fields = fields.grep(/\Aeproc \d+\z/)
      directions = fields & %w[in out]
      unless fields.all? { |field| /\A(?:e?proc \d+|in|out)\z/.match?(field) } &&
             proc_fields.length == 1 && effective_fields.length <= 1 &&
             directions.length == 1 && fields.uniq == fields
        @unparsed_lines += 1
        next
      end
      proc_pid = proc_fields.first.delete_prefix('proc ').to_i
      effective_pid = effective_fields.first&.delete_prefix('eproc ')&.to_i
      @observations << [proc_pid, effective_pid, directions.first]
    end
  end

  def stop_observer
    return unless @observer_pid
    Process.kill('INT', -@observer_pid) rescue Errno::ESRCH
    @result[:observer_exit] = wait_child(@observer_pid)
    @observer_pid = nil
  rescue StandardError => error
    @result[:observer_stop_error_type] = error.class.name
    Process.kill('KILL', -@observer_pid) rescue Errno::ESRCH
    Process.waitpid(@observer_pid) rescue Errno::ECHILD
    @observer_pid = nil
  end

  def stop_sender
    return unless @sender_pid
    @result[:sender_exit] = wait_child(@sender_pid)
    @sender_pid = nil
  rescue StandardError => error
    @result[:sender_stop_error_type] = error.class.name
    Process.kill('KILL', -@sender_pid) rescue Errno::ESRCH
    Process.waitpid(@sender_pid) rescue Errno::ECHILD
    @sender_pid = nil
  end

  def wait_child(pid)
    Timeout.timeout(4) { Process.waitpid2(pid).last.exitstatus }
  rescue Timeout::Error
    Process.kill('TERM', -pid) rescue Errno::ESRCH
    begin
      Timeout.timeout(2) { Process.waitpid2(pid).last.exitstatus }
    rescue Timeout::Error
      Process.kill('KILL', -pid) rescue Errno::ESRCH
      Process.waitpid2(pid).last.exitstatus
    end
  rescue Errno::ECHILD
    nil
  end

  def drain_remaining
    Timeout.timeout(2) { drain_once(0.1) until @readers.empty? }
  rescue Timeout::Error
    @result[:drain_timeout] = true
  rescue StandardError => error
    @result[:drain_error_type] = error.class.name
  end

  def stop_target
    @target_hold&.close
    return unless @target_pid
    Timeout.timeout(2) { Process.waitpid(@target_pid) }
  rescue Timeout::Error
    Process.kill('TERM', @target_pid) rescue Errno::ESRCH
    Process.waitpid(@target_pid) rescue Errno::ECHILD
  rescue Errno::ECHILD
    nil
  end

  def finish
    sender = JSON.parse(@buffers[:sender_stdout]) rescue nil
    @result[:control_sent] = sender['sent'] if sender.is_a?(Hash) && sender['sent'].is_a?(Integer)
    @result[:delegate_error_type] = sender['error_type'] if sender.is_a?(Hash) && sender['error_type'].is_a?(String)
    sender_pid = sender['pid'] if sender.is_a?(Hash) && sender['pid'].is_a?(Integer)
    @result[:delegated_out] = @observations.count do |proc_pid, effective_pid, direction|
      proc_pid == sender_pid && effective_pid == @target_pid && direction == 'out'
    end
    @result[:receiver_in] = @observations.count do |proc_pid, _, direction|
      proc_pid == Process.pid && direction == 'in'
    end
    @result[:other_packet_lines] = @observations.length - @result[:delegated_out] - @result[:receiver_in]
    @result[:packet_lines] = @packet_lines
    @result[:unparsed_lines] = @unparsed_lines
    @result[:blank_lines] = @blank_lines
    @result[:unterminated_packet_bytes] = @buffers[:observer_stdout].bytesize
    stderr = @buffers[:observer_stderr]
    @result[:stderr_lines] = stderr.lines.count
    @result[:unknown_stderr_lines] = stderr.lines.count do |line|
      !/\A(?:tcpdump: verbose output suppressed, use -v\[v\]\.\.\. for full protocol decode|tcpdump: data link type [^\r\n]+|(?:tcpdump: )?listening on pktap,lo0, link-type [^\r\n]+, snapshot length 256 bytes|\d+ packets? captured|\d+ packets? received by filter|\d+ packets? dropped by kernel)\n\z/.match?(line)
    end
    @result[:captured_count] = stderr[/^(\d+) packets? captured$/, 1]&.to_i
    @result[:kernel_drops] = stderr[/^(\d+) packets? dropped by kernel$/, 1]&.to_i
    @result[:control_received] = 0
    if @receiver
      received_total = 0
      loop do
        data = @receiver.recv_nonblock(64, exception: false)
        break if data == :wait_readable
        received_total += 1
        if received_total > 64
          @result[:receiver_limit_exceeded] = true
          break
        end
        if data == 'synthetic-control'
          @result[:control_received] += 1
        else
          @result[:unexpected_received] = @result.fetch(:unexpected_received, 0) + 1
        end
      end
    end
    if @result[:delegate_error_type] == 'Errno::EACCES'
      @result[:outcome] = 'blocked-delegation-privilege'
    elsif !@result[:error_type] && !@result[:observer_stop_error_type] &&
          !@result[:sender_stop_error_type] && !@result[:drain_error_type] &&
          @result[:observer_ready] && @result[:full_window] &&
          @result[:observer_exit] == 0 && @result[:sender_exit] == 0 &&
          @result[:control_sent] == 4 && @result[:control_received] == 4 &&
          @result[:delegated_out] == 4 && @result[:receiver_in] == 4 &&
          @result[:other_packet_lines] == 0 && !@result[:unexpected_received] &&
          !@result[:receiver_limit_exceeded] &&
          @result[:captured_count] == @packet_lines &&
          @result[:kernel_drops] == 0 && @unparsed_lines == 0 &&
          @result[:unterminated_packet_bytes] == 0 && !@result[:drain_timeout] &&
          @result[:unknown_stderr_lines] == 0 && @buffers[:sender_stderr].empty?
      @result[:outcome] = 'synthetic-delegation-observed'
    end
    puts JSON.pretty_generate(@result)
  end
end

if $PROGRAM_NAME == __FILE__
  unless [%w[--help], %w[--check], %w[--run]].include?(ARGV)
    warn USAGE
    exit 1
  end
  if ARGV == ['--help']
    puts USAGE
    exit 0
  end
  begin
    validate_environment
  rescue StandardError => error
    warn error.message
    exit 1
  end
  if ARGV == ['--check']
    puts JSON.generate(kind: 'synthetic-delegated-loopback', outcome: 'prepared',
                       product_pass: false, sudo_used: false, network_capture: false)
    exit 0
  end
  trial = DelegatedLoopbackTrial.new
  trial.run
  exit(trial.result[:outcome] == 'synthetic-delegation-observed' ? 0 : 2)
end
