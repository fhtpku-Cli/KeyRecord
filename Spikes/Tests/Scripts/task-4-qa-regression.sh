#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-task4-regression.XXXXXX")"
cleanup() { local status=$?; trap - EXIT; rm -rf "$tmp_dir"; exit "$status"; }
trap cleanup EXIT INT TERM HUP

clone_and_run() {
  local mode="$1"
  local repository="$tmp_dir/$mode"
  GIT_MASTER=1 git clone --quiet "$repo_root" "$repository"
  [[ ! -e "$repository/.omo/evidence" ]]
  (cd "$repository" && bash Spikes/Scripts/run-task-qa.sh 4 "$mode")
  /usr/bin/grep -Eq '^TASK_4_(HAPPY|NEGATIVE)=PASS$' "$repository/.omo/evidence/task-4-phase-0-validation${mode/happy/}.txt" 2>/dev/null \
    || /usr/bin/grep -Eq '^TASK_4_(HAPPY|NEGATIVE)=PASS$' "$repository/.omo/evidence/task-4-phase-0-validation-failure.txt"
}

assert_interrupted_removes_stale_pass() {
  local signal="$1" expected_status="$2"
  local repository="$tmp_dir/happy"
  local output="$repository/.omo/evidence/task-4-phase-0-validation.txt"
  printf 'TASK_4_HAPPY=PASS\nSTALE=YES\n' >"$output"
  /usr/bin/perl -e '
    use strict; use warnings; use Time::HiRes qw(usleep);
    my ($repository, $output, $signal, $expected, $log) = @ARGV;
    my $pid = fork(); die "fork: $!" unless defined $pid;
    if ($pid == 0) {
      chdir $repository or die "chdir: $!";
      open STDOUT, ">", $log or die "stdout: $!";
      open STDERR, ">&STDOUT" or die "stderr: $!";
      exec "/bin/bash", "Spikes/Scripts/run-task-qa.sh", "4", "happy";
      die "exec: $!";
    }
    my $removed = 0;
    for (1..200) { if (!-e $output) { $removed = 1; last; } usleep(10_000); }
    kill $signal, $pid;
    waitpid($pid, 0);
    my $status = $? >> 8;
    exit(($removed && $status == $expected && !-e $output) ? 0 : 1);
  ' "$repository" "$output" "$signal" "$expected_status" "$tmp_dir/$signal.log"
}

clone_and_run happy
clone_and_run failure
assert_interrupted_removes_stale_pass TERM 143
assert_interrupted_removes_stale_pass INT 130

printf 'TASK_4_QA_REGRESSION=PASS fresh_happy=PASS fresh_failure=PASS stale_term=REMOVED stale_int=REMOVED\n'
