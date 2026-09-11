#!/usr/bin/env bash
set -euo pipefail
# Registry schemaVersion=1: cases contain task, case, exact argv, expectedKind
# (xctest), timeoutSeconds, minTestCount. Only {attempt}/build/spikes is expanded.
# No CLI command override or eval. Ruby's standard library supplies JSON, exclusive
# receipts and process-group timeouts; missing Ruby is BLOCKED, never PASS.
command -v ruby >/dev/null || { printf 'outcome=BLOCKED code=missing_ruby\n' >&2; exit 2; }
exec ruby - "$0" "$@" <<'RUBY'
require 'json'
require 'pathname'
require 'time'

class Rejection < StandardError; end
def reject(code)
  raise Rejection, code
end
def exclusive(path, content)
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0600) { |f| f.write(content) }
end
def safe_directory(path, root)
  reject('invalid_attempt') unless path.start_with?(root + '/') && !path.split('/').include?('..')
  reject('invalid_attempt') unless Pathname.new(path).absolute? && File.expand_path(path) == path
  current = ''
  path.split('/').reject(&:empty?).each do |component|
    current += '/' + component
    reject('invalid_attempt') if File.symlink?(current)
    begin
      Dir.mkdir(current, 0700) unless File.exist?(current)
    rescue Errno::EEXIST
      # Another creator must still satisfy the same ownership/type checks below.
    end
    reject('invalid_attempt') unless File.directory?(current) && !File.symlink?(current)
    if current.start_with?(root + '/')
      reject('invalid_attempt') unless File.stat(current).uid == Process.uid && File.writable?(current)
    end
  end
  reject('invalid_attempt') unless File.realpath(path) == path
end

begin
  script = ARGV.shift
  root = File.dirname(File.dirname(File.realpath(script)))
  mode = ARGV.shift
  case mode
  when 'task'
    reject('invalid_arguments') unless ARGV.length == 4 && ARGV[2] == '--attempt'
    task, name, _, attempt = ARGV
    reject('unknown_task_case') unless task.match?(/\A[1-9][0-9]*\z/) && %w[happy failure].include?(name)
  when 'host'
    reject('invalid_arguments') unless ARGV.length == 5 && ARGV[1] == '--manifest' && ARGV[3] == '--attempt'
    reject('unregistered_host')
  else
    reject('invalid_arguments')
  end
  registry = JSON.parse(File.read(File.join(root, 'Scripts/phase1-qa-cases.json'), encoding: 'UTF-8'))
  reject('invalid_registry') unless registry['schemaVersion'] == 1 && registry['cases'].is_a?(Array)
  entries = registry['cases'].select { |e| e.is_a?(Hash) && e['task'] == task.to_i && e['case'] == name }
  reject('unknown_task_case') if entries.empty?
  reject('invalid_registry') unless entries.length == 1
  entry = entries.first
  argv = entry['argv']
  minimum = entry['minTestCount']
  reject('invalid_registry') unless entry['expectedKind'] == 'xctest' && minimum.is_a?(Integer) && minimum > 0
  reject('invalid_registry') unless argv.is_a?(Array) && !argv.empty? && argv.all? { |v| v.is_a?(String) && !v.empty? && !v.include?("\0") }
  timeout = Float(ENV.fetch('PHASE1_QA_TIMEOUT_SECONDS', entry.fetch('timeoutSeconds', 1200)))
  reject('invalid_timeout') unless timeout.finite? && timeout > 0
  safe_directory(attempt, root)
  parent = File.join(attempt, 'task-' + task)
  safe_directory(parent, root)
  result = File.join(parent, name)
  begin
    Dir.mkdir(result, 0700)
  rescue Errno::EEXIST
    reject('attempt_reused')
  end
  argv = argv.map { |v| v == '{attempt}/build/spikes' ? File.join(attempt, 'build/spikes') : v }
  exclusive(File.join(result, 'command.json'), JSON.pretty_generate(argv) + "\n")
  stdout = File.open(File.join(result, 'stdout'), File::WRONLY | File::CREAT | File::EXCL, 0600)
  stderr = File.open(File.join(result, 'stderr'), File::WRONLY | File::CREAT | File::EXCL, 0600)
  pid = nil
  timed_out = false
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  begin
    pid = Process.spawn({'PHASE1_QA_ATTEMPT' => attempt}, [argv.first, argv.first], *argv.drop(1), chdir: root, out: stdout, err: stderr, pgroup: true)
    status = nil
    until status
      waited = Process.waitpid2(pid, Process::WNOHANG)
      status = waited[1] if waited
      if !status && Process.clock_gettime(Process::CLOCK_MONOTONIC) - started >= timeout
        timed_out = true
        Process.kill('KILL', -pid)
        status = Process.waitpid2(pid)[1]
      end
      sleep 0.02 unless status
    end
    child_exit = status.exitstatus || 128 + status.termsig
  rescue Errno::ENOENT, Errno::EACCES => error
    stderr.puts(error.class.name)
    child_exit = 127
  ensure
    # The child owns a fresh group; reap descendants even if its leader exits first.
    if pid
      begin
        Process.kill('KILL', -pid)
      rescue Errno::ESRCH
      end
    end
    stdout.close
    stderr.close
  end
  text = File.read(File.join(result, 'stdout'), encoding: 'UTF-8').scrub + "\n" + File.read(File.join(result, 'stderr'), encoding: 'UTF-8').scrub
  counts = text.scan(/Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?/)
  executed = counts.map { |c| c[0].to_i }.max || 0
  skipped = [counts.map { |c| c[1].to_i }.max || 0, text.scan(/Test Case .* skipped/).length].max
  failed = [counts.map { |c| c[2].to_i }.max || 0, text.scan(/Test Case .* failed/).length].max
  completed = text.scan(/Test Case .* (?:passed|failed|skipped) \(/).length
  code = if timed_out then 'child_timeout'
         elsif child_exit == 127 then 'missing_executable'
         elsif child_exit != 0 then 'child_failed'
         elsif skipped > 0 then 'skipped_tests'
         elsif failed > 0 then 'assertions_failed'
         elsif executed < minimum then 'insufficient_tests'
         elsif completed != executed then 'incomplete_test_output'
         else 'assertions_passed'
         end
  outcome = code == 'assertions_passed' ? 'PASS' : (child_exit == 127 ? 'BLOCKED' : 'FAIL')
  exit_status = outcome == 'PASS' ? 0 : (outcome == 'BLOCKED' ? 2 : (child_exit.zero? ? 1 : child_exit))
  exclusive(File.join(result, 'exit-status'), child_exit.to_s + "\n")
  summary = {outcome: outcome, code: code, childExitStatus: child_exit, runnerExitStatus: exit_status, executed: executed, skipped: skipped, failed: failed, timedOut: timed_out, timeoutSeconds: timeout, argv: argv}
  exclusive(File.join(result, 'assertion-summary.json'), JSON.pretty_generate(summary) + "\n")
  puts "outcome=#{outcome} code=#{code} executed=#{executed} skipped=#{skipped} child_exit=#{child_exit}"
  exit exit_status
rescue Rejection => error
  warn "outcome=FAIL code=#{error.message}"
  exit 1
rescue JSON::ParserError, KeyError, TypeError, ArgumentError
  warn 'outcome=FAIL code=invalid_registry'
  exit 1
rescue SystemCallError => error
  warn "outcome=FAIL code=filesystem_error detail=#{error.class.name}"
  exit 1
end
RUBY
