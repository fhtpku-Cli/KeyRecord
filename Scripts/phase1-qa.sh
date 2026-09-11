#!/usr/bin/env bash
set -euo pipefail
# Trust model: the committed, operator-controlled registry maps task/case to exact
# XCTest argv. The dispatcher never evaluates arbitrary command strings or CLI
# overrides. Fabricated stdout from a tampered registry is outside this trust model;
# unknown schema fields are rejected. This is not a hostile same-UID sandbox.
# SchemaVersion=1 allows only schemaVersion/cases; entries require task, case, argv,
# expectedKind (xctest), minTestCount, and optional timeoutSeconds (default 1200).
# Only {attempt}/build/spikes is expanded. Runner exits: PASS=0, FAIL=1, BLOCKED=2;
# receipts retain raw child exits. Ruby supplies JSON and process-group timeouts.
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
    begin
      before = File.lstat(current)
    rescue Errno::ENOENT
      before = nil
    end
    reject('invalid_attempt') if before && before.symlink?
    unless before
      begin
        Dir.mkdir(current, 0700)
      rescue Errno::EEXIST
        # A concurrent creator must still pass the non-following check below.
      end
    end
    stat = File.lstat(current)
    reject('invalid_attempt') unless stat.directory? && !stat.symlink?
    if current.start_with?(root + '/')
      reject('invalid_attempt') unless stat.uid == Process.uid && File.writable?(current)
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
  reject('invalid_registry') unless registry.is_a?(Hash) && registry.keys.sort == %w[cases schemaVersion]
  reject('invalid_registry') unless registry['schemaVersion'].is_a?(Integer) && registry['schemaVersion'] == 1 && registry['cases'].is_a?(Array)
  required = %w[task case argv expectedKind minTestCount]
  registry['cases'].each do |candidate|
    reject('invalid_registry') unless candidate.is_a?(Hash)
    reject('invalid_registry') unless (required - candidate.keys).empty? && (candidate.keys - required - ['timeoutSeconds']).empty?
    reject('invalid_registry') unless candidate['task'].is_a?(Integer) && candidate['task'] > 0 && %w[happy failure].include?(candidate['case'])
    reject('invalid_registry') unless candidate['expectedKind'] == 'xctest' && candidate['minTestCount'].is_a?(Integer) && candidate['minTestCount'] > 0
    args = candidate['argv']
    reject('invalid_registry') unless args.is_a?(Array) && !args.empty? && args.all? { |v| v.is_a?(String) && !v.empty? && !v.include?("\0") }
    seconds = candidate.fetch('timeoutSeconds', 1200)
    reject('invalid_registry') unless (seconds.is_a?(Integer) || seconds.is_a?(Float)) && seconds.finite? && seconds > 0
  end
  identities = registry['cases'].map { |e| [e['task'], e['case']] }
  reject('invalid_registry') unless identities.uniq.length == identities.length
  entries = registry['cases'].select { |e| e['task'] == task.to_i && e['case'] == name }
  reject('unknown_task_case') if entries.empty?
  reject('invalid_registry') unless entries.length == 1
  entry = entries.first
  argv = entry['argv']
  minimum = entry['minTestCount']
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
  missing_executable = false
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
    missing_executable = true
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
         elsif missing_executable then 'missing_executable'
         elsif child_exit != 0 then 'child_failed'
         elsif skipped > 0 then 'skipped_tests'
         elsif failed > 0 then 'assertions_failed'
         elsif executed < minimum then 'insufficient_tests'
         elsif completed != executed then 'incomplete_test_output'
         else 'assertions_passed'
         end
  outcome = code == 'assertions_passed' ? 'PASS' : (missing_executable ? 'BLOCKED' : 'FAIL')
  exit_status = {'PASS' => 0, 'FAIL' => 1, 'BLOCKED' => 2}.fetch(outcome)
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
