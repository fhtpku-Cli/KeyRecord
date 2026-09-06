#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-task-qa.XXXXXX")"
final_output=""
publish_temp=""
cleanup() {
  status=$?
  trap - EXIT
  [[ "$status" -eq 0 || -z "$final_output" ]] || rm -f "$final_output"
  [[ -z "$publish_temp" ]] || rm -f "$publish_temp"
  rm -rf "$tmp_dir"
  exit "$status"
}
interrupt() {
  status="$1"
  trap - EXIT INT TERM HUP
  child_pids="$(jobs -pr)"
  if [[ -n "$child_pids" ]]; then
    kill $child_pids 2>/dev/null || true
    wait $child_pids 2>/dev/null || true
  fi
  [[ -z "$final_output" ]] || rm -f "$final_output"
  [[ -z "$publish_temp" ]] || rm -f "$publish_temp"
  rm -rf "$tmp_dir"
  exit "$status"
}
trap cleanup EXIT
trap 'interrupt 130' INT
trap 'interrupt 143' TERM
trap 'interrupt 129' HUP
script_dir="$(cd "$(dirname "$0")" && pwd)"
source "$script_dir/task-2-qa-lib.sh"

qa_build_product() {
  local log_file="$1" product="$2" scratch="$tmp_dir/swift-build" bin_path
  task2_run_logged "$log_file" swift build --package-path Spikes --scratch-path "$scratch" --product "$product" || return 1
  bin_path="$(swift build --package-path Spikes --scratch-path "$scratch" --show-bin-path)" || return 1
  [[ -x "$bin_path/$product" ]] || {
    printf 'missing_built_product=%s\n' "$bin_path/$product" >>"$log_file"
    return 1
  }
  printf '%s\n' "$bin_path/$product"
}

task4_verify_bound_runner() {
  local log_file="$1" result_file="$2" validator="$3" evidence_dir
  evidence_dir="$(dirname "$result_file")"
  task2_run_logged "$log_file" "$validator" validate-atomicity "$evidence_dir"
}

if [[ "${1:-}" != "1" && "${1:-}" != "2" && "${1:-}" != "3" && "${1:-}" != "4" && "${1:-}" != "5" && "${1:-}" != "6" && "${1:-}" != "7" && "${1:-}" != "8" && "${1:-}" != "9" && "${1:-}" != "10" ]]; then
  printf 'Task %s QA is not implemented by scaffold task 1.\n' "${1:-missing}" >&2
  exit 64
fi
