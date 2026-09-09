#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"
APP_PROBE="$HOME/Applications/KeyRecord-Phase0-Probe.app/Contents/MacOS/keyrecord-phase0-probe"
APP_UNATTR="$HOME/Applications/KeyRecord-Phase0-Unattributable.app"
SRC_UNATTR="$REPO_ROOT/Spikes/Scripts/KeyRecord-Phase0-Unattributable.app"
UNATTR_BIN="$APP_UNATTR/Contents/MacOS/keyrecord-phase0-unattributable"

notify() {
  local title="$1"
  local message="$2"
  osascript -e "display notification $(printf '%q' "$message") with title $(printf '%q' "$title") sound name \"Glass\"" >/dev/null 2>&1 || true
  printf '\n>>> %s: %s\n' "$title" "$message"
}

if [[ "${KEYRECORD_SKIP_PROBE_BUILD:-0}" != "1" ]]; then
  swift build --package-path Spikes -c release --product Phase0Probe
  mkdir -p "$(dirname "$APP_PROBE")"
  install -m 755 "$REPO_ROOT/Spikes/.build/release/Phase0Probe" "$APP_PROBE"
  codesign --force --sign - --identifier com.keyrecord.phase0.probe "$APP_PROBE" >/dev/null
fi

pkill -f 'KeyRecord-Phase0-Unattributable.app/Contents/MacOS/keyrecord-phase0-unattributable' 2>/dev/null || true
if [[ -d "$SRC_UNATTR" ]]; then
  rm -rf "$APP_UNATTR"
  cp -R "$SRC_UNATTR" "$APP_UNATTR"
  swiftc -O -o "$UNATTR_BIN" "$REPO_ROOT/Spikes/Scripts/keyrecord-phase0-unattributable.swift" -framework AppKit
  codesign --force --sign - "$APP_UNATTR" >/dev/null 2>&1 || true
  open "$APP_UNATTR"
  sleep 1
fi

PROBE="${KEYRECORD_PROBE:-$APP_PROBE}"
ENV="${1:-/tmp/keyrecord-g0-attempt/environment.json}"
OUT="${2:-/tmp/keyrecord-g0-attempt/sp2}"
WS="${KEYRECORD_SP2_WINDOW_SECONDS:-15}"
READY_SEC="${KEYRECORD_SP2_READY_SECONDS:-10}"

export KEYRECORD_SP2_LIVE_AGGREGATE_V2=1
export KEYRECORD_SP2_LIVE_EXECUTION=1
export KEYRECORD_SP2_WINDOW_SECONDS="$WS"

mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT"

"$PROBE" preflight --output "$ENV"

clear 2>/dev/null || true
cat <<EOF

========================================
SP-2 LIVE — 请看本窗口 + 右上角通知
4 个窗口，每个 ${WS} 秒
========================================
浮动窗口「KeyRecord SP-2 Window 2」已弹出（窗口 2 用）

[1/4] 本 Terminal 保持焦点 → 按 a
[2/4] 点浮动窗口 → 按 a
[3/4] Globe/Fn 按一下松开
[4/4] Globe/Fn 短按松开 × 2
========================================

EOF

notify "SP-2 Live" "请切到本 Terminal 窗口。${READY_SEC} 秒后开始，也可按 Enter 立即开始。"
read -r -p "看完说明后按 Enter 开始… "
notify "SP-2 Live" "即将开始窗口 1：在本 Terminal 按 a"

(
  sleep 2
  notify "窗口 1/4" "现在：在本 Terminal 按字母键 a"
  sleep "$WS"
  notify "窗口 2/4" "现在：点「KeyRecord SP-2 Window 2」，再按 a"
  osascript -e 'tell application "KeyRecord SP-2 W2" to activate' >/dev/null 2>&1 || \
    open "$APP_UNATTR" >/dev/null 2>&1 || true
  sleep "$WS"
  notify "窗口 3/4" "现在：Globe/Fn 按一下并松开"
  sleep "$WS"
  notify "窗口 4/4" "现在：Globe/Fn 短按松开，再短按松开"
) &

"$PROBE" sp2 --environment "$ENV" --output "$OUT"
pkill -f 'KeyRecord-Phase0-Unattributable.app/Contents/MacOS/keyrecord-phase0-unattributable' 2>/dev/null || true
notify "SP-2 Live" "采集结束。output=$OUT"
echo "SP2_LIVE_DONE output=$OUT"
read -n 1 -s -r -p "按任意键关闭本窗口… " || true
echo
