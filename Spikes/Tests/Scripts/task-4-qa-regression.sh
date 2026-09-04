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
  (cd "$repository" && exec bash Spikes/Scripts/run-task-qa.sh 4 happy) >"$tmp_dir/$signal.log" 2>&1 &
  local pid=$! status=0 removed=false
  for _ in {1..200}; do
    if [[ ! -e "$output" ]]; then removed=true; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.01
  done
  [[ "$removed" == true ]]
  kill -s "$signal" "$pid"
  set +e
  wait "$pid"
  status=$?
  set -e
  [[ "$status" -eq "$expected_status" ]]
  [[ ! -e "$output" ]]
}

clone_and_run happy
clone_and_run failure
assert_interrupted_removes_stale_pass TERM 143
assert_interrupted_removes_stale_pass INT 130

printf 'TASK_4_QA_REGRESSION=PASS fresh_happy=PASS fresh_failure=PASS stale_term=REMOVED stale_int=REMOVED\n'
