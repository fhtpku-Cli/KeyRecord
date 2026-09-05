#!/usr/bin/env bash
set -euo pipefail
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-security.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM

[[ $# -eq 2 && ( "$1" == "sp6a" || "$1" == "sp6b" ) ]] || { printf 'Usage: %s sp6a|sp6b <security-audit.md>\n' "$0" >&2; exit 64; }
mode="$1"
audit="$2"
prefix="$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')_SECURITY_AUDIT"
[[ -f "$audit" && ! -L "$audit" ]] || { printf '%s=FAIL reason=invalid_file\n' "$prefix" >&2; exit 1; }
[[ "$(wc -c <"$audit")" -le 1048576 ]] || { printf '%s=FAIL reason=oversized\n' "$prefix" >&2; exit 1; }

if [[ "$mode" == "sp6a" ]]; then
  rows=(framing-version aad-tag hmac-locator-inputs hkdf-labels key-versions nonce-policy accessibility-sync plaintext-lifetime-logging errors cleanup atomicity)
else
  rows=(pins transitive-graph licenses advisories maintenance ffi-zeroization compiler-flags parameter-bounds allocation-errors vectors universal-build source-loc)
fi
for row in "${rows[@]}"; do
  count="$(/usr/bin/grep -Ec "^\\| [0-9]+ \\| ${row} \\| PASS \\| (Critical|High|Medium|Low) \\| .+ \\| .+ \\| .+ \\|$" "$audit" || true)"
  [[ "$count" == "1" ]] || { printf '%s=FAIL row=%s count=%s\n' "$prefix" "$row" "$count" >&2; exit 1; }
done
[[ "$(/usr/bin/grep -Ec '^\| [0-9]+ \| ' "$audit" || true)" == "${#rows[@]}" ]] || { printf '%s=FAIL reason=row_set\n' "$prefix" >&2; exit 1; }
/usr/bin/grep -Fq 'Unresolved severity totals: Critical: 0; High: 0; Medium: 0;' "$audit" || { printf '%s=FAIL reason=totals\n' "$prefix" >&2; exit 1; }
if /usr/bin/grep -Eq '^[^|]+ \| UNRESOLVED \| (Critical|High|Medium) \|' "$audit"; then
  printf '%s=FAIL reason=unresolved_significant\n' "$prefix" >&2
  exit 1
fi
printf '%s=PASS rows=%s unresolved_critical=0 unresolved_high=0 unresolved_medium=0\n' "$prefix" "${#rows[@]}"
