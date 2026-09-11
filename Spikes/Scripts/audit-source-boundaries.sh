#!/usr/bin/env bash
set -euo pipefail
source_root="Spikes/Sources"
if [[ "${1:-}" == "--fixture" && $# -eq 2 ]]; then source_root="$2"; elif [[ $# -ne 0 ]]; then printf 'Usage: %s [--fixture PATH]\n' "$0" >&2; exit 64; fi
[[ -d "$source_root" && ! -L "$source_root" ]] || { printf 'SOURCE_BOUNDARY_AUDIT=FAIL reason=invalid_root\n' >&2; exit 1; }

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/keyrecord-boundaries.XXXXXX")"
cleanup() { rm -rf "$tmp_dir"; }
trap cleanup EXIT INT TERM

if /usr/bin/grep -REn 'case[[:space:]]+(keymapWrite|macroWrite|eepromWrite|unlock|reset|bootloader)|IOHIDDeviceSetReport|kIOHIDReportTypeOutput' "$source_root" >"$tmp_dir/forbidden"; then
  printf 'SOURCE_BOUNDARY_AUDIT=FAIL reason=mutating_vial_api\n' >&2
  cat "$tmp_dir/forbidden" >&2
  exit 1
fi
if [[ "$source_root" != "Spikes/Sources" ]]; then printf 'SOURCE_BOUNDARY_AUDIT=PASS fixture=%s\n' "$source_root"; exit 0; fi

query="Spikes/Sources/Phase0Support/VialQuery.swift"
[[ -f "$query" ]]
/usr/bin/grep -Eq '^[[:space:]]*case protocolVersion$' "$query"
/usr/bin/grep -Eq '^[[:space:]]*case uid$' "$query"
/usr/bin/grep -Eq 'case definition\(VialDefinitionQuery\)' "$query"
/usr/bin/grep -Eq 'case keymapRead\(' "$query"
[[ "$(awk '/public enum VialQuery:/{inside=1; next} inside && /^}/{exit} inside && /^[[:space:]]*case /{count++} END{print count+0}' "$query")" -eq 4 ]] || { printf 'SOURCE_BOUNDARY_AUDIT=FAIL reason=vial_case_set\n' >&2; exit 1; }
/usr/bin/grep -Fq 'default: throw VialQueryError.invalidQuery' "$query" || { printf 'SOURCE_BOUNDARY_AUDIT=FAIL reason=deny_all_default\n' >&2; exit 1; }
if /usr/bin/grep -Rq 'IOHIDDeviceSetReport' Spikes/Sources; then printf 'SOURCE_BOUNDARY_AUDIT=FAIL reason=device_write_symbol\n' >&2; exit 1; fi
if /usr/bin/grep -REn --include='*.swift' 'CGEventPost[[:space:]]*\(|CGEventPostToPid[[:space:]]*\(|CGEventPostToPSN[[:space:]]*\(|CGEvent\.post[[:space:]]*\(' "$source_root" >"$tmp_dir/cgevent-post"; then
  printf 'SOURCE_BOUNDARY_AUDIT=FAIL reason=cgevent_post\n' >&2
  cat "$tmp_dir/cgevent-post" >&2
  exit 1
fi
if /usr/bin/grep -Eq '\.package[[:space:]]*\(' Spikes/Package.swift; then printf 'SOURCE_BOUNDARY_AUDIT=FAIL reason=external_package\n' >&2; exit 1; fi
if /usr/bin/grep -Eq 'KeyRecord(App|Core|Capture|Store|Backends)' Spikes/Package.swift; then printf 'SOURCE_BOUNDARY_AUDIT=FAIL reason=production_target\n' >&2; exit 1; fi
printf 'SOURCE_BOUNDARY_AUDIT=PASS vial=whitelist-only production_targets=0 external_packages=0\n'
