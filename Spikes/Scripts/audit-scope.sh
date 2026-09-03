#!/usr/bin/env bash
set -euo pipefail
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-scope.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM
printf 'Scope auditing is not implemented until the final wave.\n' >&2
exit 64
