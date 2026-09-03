#!/usr/bin/env bash
set -euo pipefail
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-fixtures.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM
printf 'Synthetic fixture generation is not implemented until plan task 2.\n' >&2
exit 64
