#!/usr/bin/env bash
set -euo pipefail
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-boundaries.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM
printf 'Source-boundary auditing is not implemented until later Phase 0 tasks.\n' >&2
exit 64
