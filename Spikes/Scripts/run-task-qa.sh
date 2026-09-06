#!/usr/bin/env bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
task="${1:-}"
case "$task" in
  16|15|14|13|12|11) exec bash "$script_dir/task-${task}-qa.sh" "${2:-}" ;;
  10) exec bash "$script_dir/task-qa-10.sh" "$@" ;;
  8|9) exec bash "$script_dir/task-qa-8-9.sh" "$@" ;;
  5|6|7) exec bash "$script_dir/task-qa-5-7.sh" "$@" ;;
  1|2|3|4) exec bash "$script_dir/task-qa-1-4.sh" "$@" ;;
  *) printf "Task %s QA is not implemented by scaffold task 1.\n" "${task:-missing}" >&2; exit 64 ;;
esac
