#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
PROBE="${KEYRECORD_PROBE:-$HOME/Applications/KeyRecord-Phase0-Probe.app/Contents/MacOS/keyrecord-phase0-probe}"
K="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
ENV="${1:-/tmp/keyrecord-g0-attempt/environment.json}"
OUT="${2:-/tmp/keyrecord-g0-attempt/sp1}"
WS="${KEYRECORD_SP1_WINDOW_SECONDS:-20}"
HIDUTIL_ON='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x7000000E6,"HIDKeyboardModifierMappingDst":0x70000006D}]}'
HIDUTIL_ON_F19='{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0x7000000E6,"HIDKeyboardModifierMappingDst":0x70000006E}]}'
HIDUTIL_OFF='{"UserKeyMapping":[]}'

export KEYRECORD_SP1_LIVE_EXECUTION=1
export KEYRECORD_SP1_WINDOW_SECONDS="$WS"

mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT"

"$PROBE" preflight --output "$ENV"

hidutil_off() { hidutil property --set "$HIDUTIL_OFF" >/dev/null || true; }
hidutil_on_f18() { hidutil property --set "$HIDUTIL_ON" >/dev/null || true; }
hidutil_on_f19() { hidutil property --set "$HIDUTIL_ON_F19" >/dev/null || true; }
cleanup() {
  hidutil_off
  "$K" --select-profile "KeyRecord-Phase0-SP1" 2>/dev/null || true
}
trap cleanup EXIT

say "S P one live test starting. First ${WS} seconds: optionally press Shift Command three and Control Up." &
(
  sleep "$WS"
  "$K" --select-profile "Default profile"
  hidutil_on_f18
  say "Session off phase. Press Right Option once now." &
  sleep "$WS"
  "$K" --select-profile "KeyRecord-Phase0-SP1"
  hidutil_on_f19
  say "Session on phase. Press Right Option once now." &
  sleep "$WS"
  "$K" --select-profile "Default profile"
  hidutil_on_f18
  say "Annotated off phase. Press Right Option once now." &
  sleep "$WS"
  "$K" --select-profile "KeyRecord-Phase0-SP1"
  hidutil_on_f19
  say "Annotated on phase. Press Right Option once now." &
) &

"$PROBE" sp1 --environment "$ENV" --output "$OUT"
echo "SP1_LIVE_DONE output=$OUT"
