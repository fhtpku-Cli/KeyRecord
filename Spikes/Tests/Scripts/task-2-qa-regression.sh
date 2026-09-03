#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../../.." && pwd)"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-task2-regression.XXXXXX")"
cleanup() { local status=$?; trap - EXIT; rm -rf "$tmp_dir"; exit "$status"; }
trap cleanup EXIT INT TERM HUP

lib="$repo_root/Spikes/Scripts/task-2-qa-lib.sh"
[[ -f "$lib" ]] || { printf 'missing regression target: %s\n' "$lib" >&2; exit 1; }
source "$lib"

if task2_run_logged "$tmp_dir/failure.log" false; then
  printf 'wrapped false unexpectedly succeeded\n' >&2
  exit 1
else
  status=$?
fi
[[ "$status" -eq 1 ]]
grep -Fx 'exit_status=1' "$tmp_dir/failure.log" >/dev/null
if task2_run_logged "$tmp_dir/chain.log" false; then
  printf 'TASK_2_HAPPY=PASS\n' >"$tmp_dir/false-pass"
fi
[[ ! -e "$tmp_dir/false-pass" ]]
set +e
task2_run_logged "$tmp_dir/explicit-no-errexit.log" false
status=$?
[[ $- != *e* ]]
set -e
[[ "$status" -eq 1 ]]

task2_privacy_scan "$repo_root/evidence/phase0/environment.json" >/dev/null

cat >"$tmp_dir/forbidden.json" <<'JSON'
{"outer":{"serialNumber":"x","identity":{"username":"x","credential":"x"}},"eventSequence":[]}
JSON
if task2_privacy_scan "$tmp_dir/forbidden.json" >/dev/null 2>"$tmp_dir/forbidden.stderr"; then
  printf 'forbidden nested environment keys unexpectedly passed\n' >&2
  exit 1
else
  status=$?
fi
[[ "$status" -eq 1 ]]
[[ ! -s "$tmp_dir/forbidden.stderr" ]]

printf 'TASK_2_QA_REGRESSION=PASS wrapped_false_status=1 valid_privacy_status=0 forbidden_privacy_status=1\n'
