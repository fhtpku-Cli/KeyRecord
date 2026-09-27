#!/usr/bin/env ruby
# A bounded, owner-started Debug product observation. Only tcpdump runs as root.
require 'json'
require 'etc'
require 'open3'
require 'optparse'
require 'securerandom'
require 'socket'
require 'timeout'
require 'tmpdir'

class ProductPacketCounts
  attr_accessor :control_port

  def initialize(control_pid)
    @control_pid = control_pid
    @by_pid = Hash.new { |hash, pid| hash[pid] = {out: 0, in: 0, unknown_direction: 0} }
    @control = {out: 0, in: 0}
    @packets = @unattributed = @unparsed = @blank = @unknown_direction = 0
    @families = Hash.new(0)
  end

  def ingest(line)
    if /\A[ \t\r]*\n\z/.match?(line)
      @blank += 1
      return
    end
    match = /\A\(([^\r\n()]*)\) (.+)\n\z/.match(line)
    unless match
      @unparsed += 1
      return
    end
    @packets += 1
    body = match[2]
    family = body.start_with?('IP6 ') ? 'ipv6' : body.start_with?('IP ') ? 'ipv4' : body.start_with?('ARP,') ? 'arp' : 'other'
    @families[family] += 1
    fields = match[1].split(', ', -1)
    pids = fields.grep(/\Aproc -?\d+\z/)
    directions = fields & %w[in out]
    valid_fields = fields.all? { |field| /\A(?:e?proc -?\d+|in|out)\z/.match?(field) }
    if !valid_fields || pids.length != 1 || pids.first.delete_prefix('proc ').to_i <= 0 ||
       fields.uniq != fields || fields.grep(/\Aeproc /).length > 1
      @unattributed += 1
      return
    end
    pid = pids.first.delete_prefix('proc ').to_i
    if directions.length != 1
      @unknown_direction += 1
      @by_pid[pid][:unknown_direction] += 1
      return
    end
    direction = directions.first.to_sym
    @by_pid[pid][direction] += 1
    if pid == @control_pid && @control_port &&
       body.include?("> 127.0.0.1.#{@control_port}: UDP")
      @control[direction] += 1
    end
  end

  def summary(product_pid)
    product = @by_pid[product_pid] || {out: 0, in: 0, unknown_direction: 0}
    other = @by_pid.sum { |pid, counts| pid == product_pid || pid == @control_pid ? 0 : counts.values.sum }
    {packets: @packets, families: @families, product: product,
     control: @control, unattributed: @unattributed,
     unknown_direction: @unknown_direction, other_process_observations: other,
     unparsed_lines: @unparsed, blank_lines: @blank}
  end
end

class ProductNetworkObservation
  attr_reader :receipt

  def initialize(app:, seconds:, check: false)
    @app = app
    @seconds = seconds
    @check = check
    @counts = ProductPacketCounts.new(Process.pid)
    @receipt = {kind: 'bounded-debug-product-network-observation', product_pass: false,
                outcome: 'invalid', source_scope: 'pktap,all; no capture filter; decoded headers only',
                delegated_process_coverage: 'unverified', stderr_blank_lines: 0,
                stderr_diagnostics: {metadata_filter_drops: 0, interface_drops: 0,
                                     compression_stats_lines: 0, warning_lines: 0}}
    @streams = []
    @buffers = {out: +'', err: +''}
    @stderr_other = 0
  end

  def run
    validate_app
    if @check
      @receipt[:outcome] = 'prepared'
      return
    end
    _processes, process_status = Open3.capture2e('/usr/bin/pgrep', '-x', 'KeyRecordApp')
    raise 'another KeyRecordApp is running' if process_status.exitstatus == 0
    raise 'cannot check running KeyRecordApp' unless process_status.exitstatus == 1
    @directory = Dir.mktmpdir('keyrecord-network-', '/private/tmp')
    File.chmod(0o700, @directory)
    @receipt[:private_receipt] = File.join(@directory, 'receipt.json')
    @receipt[:trial_store] = File.join(@directory, 'store')
    @receipt[:trial_namespace] = "com.keyrecord.trial.network#{SecureRandom.hex(8)}"
    puts 'Administrator authentication is needed only for the system tcpdump process.'
    raise 'sudo authentication failed' unless system('/usr/bin/sudo', '-v')
    start_observer
    observe
  rescue Interrupt
    @receipt[:outcome] = 'interrupted'
  rescue StandardError => error
    @receipt[:error_type] = error.class.name
  ensure
    stop_observer
    inspect_product_exit
    finish_receipt
  end

  private

  def validate_app
    raise 'macOS required' unless RUBY_PLATFORM.include?('darwin')
    raise 'controller must run as an unprivileged user' if Process.uid == 0 || Process.euid == 0 || Process.uid != Process.euid
    raise 'normal user HOME required' unless File.realpath(ENV.fetch('HOME')) == File.realpath(Etc.getpwuid(Process.uid).dir)
    @app = File.realpath(@app)
    info = File.join(@app, 'Contents/Info.plist')
    executable = File.join(@app, 'Contents/MacOS/KeyRecordApp')
    debug_dylib = File.join(@app, 'Contents/MacOS/KeyRecordApp.debug.dylib')
    raise 'missing signed Debug trial bundle' unless File.file?(info) && File.executable?(executable) && File.file?(debug_dylib)
    marker, status = Open3.capture2('/usr/libexec/PlistBuddy', '-c', 'Print :KeyRecordRequiresTrialIsolation', info)
    raise 'trial isolation marker missing' unless status.success? && marker.strip == 'true'
    bundle_id, status = Open3.capture2('/usr/libexec/PlistBuddy', '-c', 'Print :CFBundleIdentifier', info)
    raise 'trial bundle identifier invalid' unless status.success? && bundle_id.strip.start_with?('com.keyrecord.trial.')
    _output, status = Open3.capture2e('/usr/bin/codesign', '--verify', '--strict', @app)
    raise 'trial signature invalid' unless status.success?
    linked, status = Open3.capture2('/usr/bin/otool', '-L', executable)
    raise 'trial executable does not load Debug code' unless status.success? && linked.include?('@rpath/KeyRecordApp.debug.dylib')
    symbols, status = Open3.capture2('/usr/bin/nm', '-g', debug_dylib)
    raise 'trial Debug isolation code missing' unless status.success? && symbols.include?('DebugTrialIsolation') && symbols.include?('makeTrial')
    @executable = executable
    @receipt[:bundle_id] = bundle_id.strip
  end

  def start_observer
    out_r, out_w = IO.pipe
    err_r, err_w = IO.pipe
    @observer_pid = Process.spawn('/usr/bin/sudo', '-n', '/usr/sbin/tcpdump', '-nn', '-q', '-l', '-t',
                                  '-i', 'pktap,all', '-k', 'PD', '-s', '256', '-c', '50000',
                                  out: out_w, err: err_w, pgroup: true)
    out_w.close
    err_w.close
    @streams = [out_r, err_r]
    @out_r = out_r
    @err_r = err_r
    @observer_started = monotonic
    @clock_gap_start = monotonic - Process.clock_gettime(Process::CLOCK_UPTIME_RAW)
  end

  def observe
    deadline = monotonic + @seconds
    ready_at = nil
    control_sent = false
    idle_until = nil
    loop do
      drain_once
      now = monotonic
      if @ready && !control_sent
        ready_at = now
        send_control
        control_sent = true
      end
      if control_sent && !@product_pid && now - ready_at >= 1
        launch_product
        idle_until = monotonic + 10
        puts 'Trial launched. In its menu choose Start, accept first-run local aggregation consent, and confirm Collecting. If it stays Blocked or prompts for permission/restart, Quit normally and report that state.'
      end
      if idle_until && now >= idle_until
        waited = Process.waitpid2(@product_pid, Process::WNOHANG)
        if waited
          @product_reaped = true
          @receipt[:product_exited] = true
          @receipt[:product_exit] = waited.last.exitstatus
          @receipt[:early_product_exit] = true
          break
        end
        @receipt[:idle_timer_elapsed] = true
        puts 'Ten seconds since launch. After Collecting is visible, leave it idle for another 10 seconds, then use only agreed short input in a normal text window and Quit from its menu.'
        idle_until = nil
      end
      break if now >= deadline || (!@ready && now - @observer_started >= 5) || @streams.empty?
    end
    @receipt[:observer_ready] = !!@ready
    @receipt[:capture_seconds] = ready_at ? (monotonic - ready_at).round(2) : 0
    @receipt[:sleep_interrupted] = ((monotonic - Process.clock_gettime(Process::CLOCK_UPTIME_RAW)) - @clock_gap_start).abs > 0.5
    @receipt[:product_pid] = @product_pid
    @receipt[:full_window] = monotonic >= deadline
  end

  def send_control
    receiver = UDPSocket.new
    sender = UDPSocket.new
    receiver.bind('127.0.0.1', 0)
    @counts.control_port = receiver.addr[1]
    4.times { sender.send('synthetic-control', 0, '127.0.0.1', @counts.control_port) }
    received = 0
    Timeout.timeout(2) do
      while received < 4
        data = receiver.recv(64)
        raise 'control payload mismatch' unless data == 'synthetic-control'
        received += 1
      end
    end
    @receipt[:control_sent] = 4
    @receipt[:control_received] = received
  ensure
    sender&.close
    receiver&.close
  end

  def launch_product
    environment = ENV.keys.grep(/\A(?:KEYRECORD_|DYLD_|__XPC_DYLD_)/).to_h { |name| [name, nil] }.merge(
      'KEYRECORD_TRIAL_STORE' => @receipt[:trial_store],
      'KEYRECORD_TRIAL_NAMESPACE' => @receipt[:trial_namespace],
      'KEYRECORD_LOCAL_CAPTURE' => '1',
      'KEYRECORD_DIAGNOSTIC_SUMMARY_PATH' => File.join(@directory, 'product-summary.json'),
      'CFFIXED_USER_HOME' => nil
    )
    @product_pid = Process.spawn(environment, @executable, out: File::NULL, err: File::NULL)
  end

  def drain_once
    selected = IO.select(@streams, nil, nil, 0.2)
    return unless selected
    selected[0].each do |io|
      chunk = io.read_nonblock(4096, exception: false)
      if chunk.nil?
        @streams.delete(io)
      elsif chunk != :wait_readable
        key = io == @out_r ? :out : :err
        @buffers[key] << chunk
        raise 'observer line too long' if @buffers[key].bytesize > 8192 && !@buffers[key].include?("\n")
        while (end_index = @buffers[key].index("\n"))
          line = @buffers[key].slice!(0..end_index)
          key == :out ? @counts.ingest(line) : ingest_stderr(line)
        end
      end
    end
  end

  def ingest_stderr(line)
    if /\A[ \t\r]*\n\z/.match?(line)
      @receipt[:stderr_blank_lines] += 1
      return
    end
    @ready = true if line.include?('listening on pktap')
    if (match = /\A(\d+) packets? captured\n\z/.match(line))
      @receipt[:captured_count] = match[1].to_i
    elsif (match = /\A(\d+) packets? dropped by kernel\n\z/.match(line))
      @receipt[:kernel_drops] = match[1].to_i
    elsif (match = /\A(\d+) drops? by metadata filter\n\z/.match(line))
      @receipt[:stderr_diagnostics][:metadata_filter_drops] =
        [@receipt[:stderr_diagnostics][:metadata_filter_drops], match[1].to_i].max
    elsif (match = /\A(\d+) packets? dropped by interface\n\z/.match(line))
      @receipt[:stderr_diagnostics][:interface_drops] =
        [@receipt[:stderr_diagnostics][:interface_drops], match[1].to_i].max
    elsif /\Acomp_stats: [^\r\n]*\n\z/.match?(line)
      @receipt[:stderr_diagnostics][:compression_stats_lines] += 1
    elsif /\Atcpdump: WARNING: [^\r\n]*\n\z/.match?(line)
      @receipt[:stderr_diagnostics][:warning_lines] += 1
    elsif /\A(?:tcpdump: verbose output suppressed|tcpdump: data link type |tcpdump: listening on |\d+ packets? received by filter)/.match?(line)
      nil
    else
      @stderr_other += 1
    end
  end

  def stop_observer
    return unless @observer_pid
    Process.kill('INT', -@observer_pid) rescue Errno::ESRCH
    begin
      Timeout.timeout(4) do
        drain_once until @streams.empty?
        @receipt[:observer_exit] = Process.waitpid2(@observer_pid).last.exitstatus
      end
    rescue Timeout::Error
      Process.kill('TERM', -@observer_pid) rescue Errno::ESRCH
      @receipt[:observer_stop_timeout] = true
      begin
        Timeout.timeout(2) { Process.waitpid(@observer_pid) }
      rescue Timeout::Error
        Process.kill('KILL', -@observer_pid) rescue Errno::ESRCH
        Process.waitpid(@observer_pid) rescue Errno::ECHILD
      end
    end
    @receipt[:unterminated_output_bytes] = @buffers[:out].bytesize
  ensure
    @streams.each { |io| io.close unless io.closed? }
  end

  def inspect_product_exit
    return unless @product_pid
    unless @product_reaped
      waited = Process.waitpid2(@product_pid, Process::WNOHANG)
      @receipt[:product_exited] = !waited.nil?
      @receipt[:product_exit] = waited.last.exitstatus if waited
      puts 'Trial remains open. Quit it normally from its menu; this observation is incomplete.' unless waited
    end
    summary_path = File.join(@directory, 'product-summary.json')
    return unless File.file?(summary_path)
    summary = JSON.parse(File.read(summary_path))
    @receipt[:product_aggregate_delta] = summary['aggregateDelta'] if summary['aggregateDelta'].is_a?(Integer)
    @receipt[:product_flush_durable] = summary['flushDurable'] if summary['flushDurable'].is_a?(Integer)
  rescue JSON::ParserError
    @receipt[:product_summary_invalid] = true
  end

  def finish_receipt
    @receipt[:counts] = @counts.summary(@product_pid)
    @receipt[:stderr_other_lines] = @stderr_other
    @receipt[:unterminated_stderr_bytes] = @buffers[:err].bytesize
    valid = !@receipt[:error_type] && @receipt[:observer_ready] && @receipt[:full_window] && @receipt[:idle_timer_elapsed] &&
            !@receipt[:early_product_exit] &&
            @receipt[:observer_exit] == 0 &&
            @receipt[:kernel_drops] == 0 && @receipt[:captured_count] == @receipt.dig(:counts, :packets) &&
            @receipt[:control_sent] == 4 && @receipt[:control_received] == 4 &&
            @receipt.dig(:counts, :control, :out) == 4 && @receipt.dig(:counts, :control, :in) == 4 &&
            @receipt[:product_exited] && @receipt[:product_exit] == 0 &&
            @receipt[:product_aggregate_delta].to_i > 0 &&
            @receipt[:unterminated_output_bytes] == 0 && @receipt[:stderr_other_lines] == 0 &&
            @receipt[:unterminated_stderr_bytes] == 0 &&
            @receipt[:stderr_diagnostics].values.all?(&:zero?) &&
            @receipt.dig(:counts, :unparsed_lines) == 0 && !@receipt[:sleep_interrupted] &&
            @receipt[:outcome] != 'interrupted'
    if valid
      @receipt[:outcome] = @receipt.dig(:counts, :product, :out) > 0 ?
        'attributed-product-outbound-observed' : 'bounded-no-attributed-outbound-observed'
    end
    if @directory
      File.write(@receipt[:private_receipt], JSON.pretty_generate(@receipt) + "\n", mode: 'w', perm: 0o600)
    end
    puts JSON.pretty_generate(@receipt)
  end

  def monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end

if $PROGRAM_NAME == __FILE__
  options = {seconds: 75, check: false}
  parser = OptionParser.new do |opts|
    opts.banner = 'Usage: ruby Scripts/product-network-observe.rb --app /absolute/KeyRecordApp.app [--seconds 75]'
    opts.on('--app PATH', 'Separate signed, isolation-marked Debug trial bundle') { |value| options[:app] = value }
    opts.on('--seconds N', Integer, 'Bounded total observer window (45..90 seconds)') { |value| options[:seconds] = value }
    opts.on('--check', 'Verify signed isolated bundle without sudo, capture, or launch') { options[:check] = true }
    opts.on('--help', 'Print help without capture or authentication') { puts opts; exit 0 }
  end
  begin
    parser.parse!
    raise OptionParser::MissingArgument, '--app' unless options[:app]
    raise OptionParser::InvalidArgument, 'seconds must be 45..90' unless (45..90).cover?(options[:seconds])
    raise OptionParser::InvalidArgument, 'unexpected arguments' unless ARGV.empty?
  rescue OptionParser::ParseError => error
    warn error.message
    warn parser
    exit 1
  end
  observation = ProductNetworkObservation.new(**options)
  observation.run
  exit(%w[prepared attributed-product-outbound-observed bounded-no-attributed-outbound-observed].include?(observation.receipt[:outcome]) ? 0 : 2)
end
