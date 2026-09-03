#!/usr/bin/env bash
set -euo pipefail

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-task-1-qa.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM

if [[ "${1:-}" != "1" ]]; then
  printf 'Task %s QA is not implemented by scaffold task 1.\n' "${1:-missing}" >&2
  exit 64
fi

case "${2:-}" in
  happy)
    output=".omo/evidence/task-1-phase-0-validation.txt"
    if swift test --package-path Spikes --filter EvidenceModelsTests >"$tmp_dir/test.log" 2>&1; then
      { printf 'TASK_1_HAPPY=PASS\n'; cat "$tmp_dir/test.log"; } >"$output"
    else
      { printf 'TASK_1_HAPPY=FAIL\n'; cat "$tmp_dir/test.log"; } >"$output"
      exit 1
    fi
    ;;
  failure)
    output=".omo/evidence/task-1-phase-0-validation-failure.txt"
    if swift test --package-path Spikes --filter 'EvidenceModelsTests.testUnknownVerdictRejects|EvidenceModelsTests.testPassWithoutArtifactHashRejects' >"$tmp_dir/test.log" 2>&1; then
      { printf 'TASK_1_NEGATIVE=PASS\nOBSERVABLE=unsupported verdict and PASS-without-artifact-hash rejected\n'; cat "$tmp_dir/test.log"; } >"$output"
    else
      { printf 'TASK_1_NEGATIVE=FAIL\n'; cat "$tmp_dir/test.log"; } >"$output"
      exit 1
    fi
    ;;
  *)
    printf 'Usage: %s 1 happy|failure\n' "$0" >&2
    exit 64
    ;;
esac

/usr/bin/head -n 1 "$output"
