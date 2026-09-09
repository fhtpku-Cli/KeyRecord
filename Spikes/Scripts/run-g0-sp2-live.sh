#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
APP_PROBE="$HOME/Applications/KeyRecord-Phase0-Probe.app/Contents/MacOS/keyrecord-phase0-probe"
if [[ "${KEYRECORD_SKIP_PROBE_BUILD:-0}" != "1" ]]; then
  swift build --package-path Spikes -c release --product Phase0Probe
  mkdir -p "$(dirname "$APP_PROBE")"
  install -m 755 "$REPO_ROOT/Spikes/.build/release/Phase0Probe" "$APP_PROBE"
  codesign --force --sign - --identifier com.keyrecord.phase0.probe "$APP_PROBE" >/dev/null
fi
PROBE="${KEYRECORD_PROBE:-$APP_PROBE}"
ENV="${1:-/tmp/keyrecord-g0-attempt/environment.json}"
OUT="${2:-/tmp/keyrecord-g0-attempt/sp2}"
WS="${KEYRECORD_SP2_WINDOW_SECONDS:-15}"

export KEYRECORD_SP2_LIVE_AGGREGATE_V2=1
export KEYRECORD_SP2_LIVE_EXECUTION=1
export KEYRECORD_SP2_WINDOW_SECONDS="$WS"

mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT"

"$PROBE" preflight --output "$ENV"

say "S P two live test. Window one: press any letter key while this terminal is focused." &
(
  sleep "$WS"
  say "Window two: click the desktop wallpaper, then press any letter key." &
  sleep "$WS"
  say "Window three: press and hold the Globe or Fn key." &
  sleep "$WS"
  say "Window four: release Globe or Fn, press it once, release, then press once more." &
) &

"$PROBE" sp2 --environment "$ENV" --output "$OUT"
echo "SP2_LIVE_DONE output=$OUT"
