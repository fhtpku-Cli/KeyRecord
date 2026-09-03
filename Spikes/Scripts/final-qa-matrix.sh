#!/usr/bin/env bash
set -euo pipefail
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-final-qa.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM
printf 'Final QA is not implemented until the final wave.\n' >&2
exit 64
