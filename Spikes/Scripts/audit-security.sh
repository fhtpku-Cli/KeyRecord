#!/usr/bin/env bash
set -euo pipefail
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-security.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM

[[ "${1:-}" == "sp6a" && $# -eq 2 ]] || { printf 'Usage: %s sp6a <security-audit.md>\n' "$0" >&2; exit 64; }
audit="$2"
[[ -f "$audit" && ! -L "$audit" ]] || { printf 'SP6A_SECURITY_AUDIT=FAIL reason=invalid_file\n' >&2; exit 1; }
[[ "$(wc -c <"$audit")" -le 1048576 ]] || { printf 'SP6A_SECURITY_AUDIT=FAIL reason=oversized\n' >&2; exit 1; }

rows=(framing-version aad-tag hmac-locator-inputs hkdf-labels key-versions nonce-policy accessibility-sync plaintext-lifetime-logging errors cleanup atomicity)
for row in "${rows[@]}"; do
  count="$(/usr/bin/grep -Ec "^\\| [0-9]+ \\| ${row} \\| PASS \\| (Critical|High|Medium|Low) \\| .+ \\| .+ \\| .+ \\|$" "$audit" || true)"
  [[ "$count" == "1" ]] || { printf 'SP6A_SECURITY_AUDIT=FAIL row=%s count=%s\n' "$row" "$count" >&2; exit 1; }
done
[[ "$(/usr/bin/grep -Ec '^\| [0-9]+ \| ' "$audit" || true)" == "11" ]] || { printf 'SP6A_SECURITY_AUDIT=FAIL reason=row_set\n' >&2; exit 1; }
/usr/bin/grep -Fq 'Unresolved severity totals: Critical: 0; High: 0; Medium: 0;' "$audit" || { printf 'SP6A_SECURITY_AUDIT=FAIL reason=totals\n' >&2; exit 1; }
if /usr/bin/grep -Eq '^[^|]+ \| UNRESOLVED \| (Critical|High|Medium) \|' "$audit"; then
  printf 'SP6A_SECURITY_AUDIT=FAIL reason=unresolved_significant\n' >&2
  exit 1
fi
printf 'SP6A_SECURITY_AUDIT=PASS rows=11 unresolved_critical=0 unresolved_high=0 unresolved_medium=0\n'
