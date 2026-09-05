#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-sp6a-cold-happy.XXXXXX")"
cleanup() { rm -rf "$temporary"; }
trap cleanup EXIT INT TERM HUP

git clone -q "$root" "$temporary/repository"
(
  cd "$temporary/repository"
  unset KEYRECORD_SP6A_ATTEMPT_HISTORY KEYRECORD_SP6A_HISTORY_ANCHOR
  bash Spikes/Scripts/run-task-qa.sh 10 happy
)
