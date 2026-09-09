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
D3S="${KEYRECORD_SP2_D3_SECONDS:-15}"
READY_SEC="${KEYRECORD_SP2_READY_SECONDS:-10}"

export KEYRECORD_SP2_LIVE_AGGREGATE_V2=1
export KEYRECORD_SP2_LIVE_EXECUTION=1
export KEYRECORD_SP2_WINDOW_SECONDS="$WS"
export KEYRECORD_SP2_D3_SECONDS="$D3S"

mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT"

"$PROBE" preflight --output "$ENV"

SUDO_OK="$(python3 -c "import json; print('yes' if json.load(open('$ENV'))['sudoNonInteractive'] else 'no')")"
D4_LIVE=0
if [[ "$SUDO_OK" == "yes" && "${KEYRECORD_ENABLE_D4:-0}" == "1" ]]; then
  export KEYRECORD_SP2_D4_LIVE=1
  D4_LIVE=1
else
  export KEYRECORD_SP2_D4_LIVE=0
fi

clear 2>/dev/null || true
cat <<EOF

========================================
SP-2 FULL LIVE — D1 + D3 + D4
请看本 Terminal + 右上角通知
========================================
D1 — 4 个窗口，每个 ${WS} 秒：
  [1/4] 本 Terminal 按 a
  [2/4] 点浮动窗「KeyRecord SP-2 Window 2」→ 按 a
  [3/4] Globe/Fn 按一下松开
  [4/4] Globe/Fn 短按松开 × 2

D3 — 窗口 5（${D3S} 秒）：
  打开「钥匙串访问」→ 双击任意项目 → 勾选「显示密码」
  （弹出密码框即 Secure Input 已激活）

D4 — sleepWake：$( [[ "$D4_LIVE" == "1" ]] && echo "已启用（窗口 5 后 Mac 将自动睡眠，唤醒后继续）" || echo "未启用（需 sudo -n + KEYRECORD_ENABLE_D4=1）" )
========================================

EOF

if [[ "$D4_LIVE" != "1" ]]; then
  echo "提示：先运行 bash Spikes/Scripts/check-g0-sp2-d34-prereqs.sh"
  echo "      D4 需配置 sudoers 后：KEYRECORD_ENABLE_D4=1 bash Spikes/Scripts/open-g0-sp2-live-terminal.sh"
  echo
fi

notify "SP-2 Live" "请切到本 Terminal。按 Enter 开始。"
read -r -p "看完说明后按 Enter 开始… "
open -a "Keychain Access" >/dev/null 2>&1 || true
notify "SP-2 Live" "窗口 1：在本 Terminal 按 a"

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
  sleep "$WS"
  notify "窗口 5/5 D3" "钥匙串访问：双击项目 → 勾选「显示密码」"
  if [[ "$D4_LIVE" == "1" ]]; then
    sleep "$((D3S > 5 ? D3S - 5 : 1))"
    notify "D4 即将睡眠" "约 5 秒后 Mac 将睡眠。唤醒后继续采集。"
  fi
) &

"$PROBE" sp2 --environment "$ENV" --output "$OUT"
pkill -f 'KeyRecord-Phase0-Unattributable.app/Contents/MacOS/keyrecord-phase0-unattributable' 2>/dev/null || true
notify "SP-2 Live" "采集结束。output=$OUT"
python3 <<PY
import json
ev=json.load(open("$OUT/evidence.json"))
for leg in sorted(ev["legs"], key=lambda x: x["legID"]):
    if leg["legID"] in ("sp2.secureInput","sp2.sleepWake") or leg["evidenceKind"]=="live":
        print(f"{leg['legID']:30} {leg['verdict']}")
print("verdict=", ev["verdict"], "o6=", ev["o6Status"])
PY
echo "SP2_LIVE_DONE output=$OUT"
read -n 1 -s -r -p "按任意键关闭本窗口… " || true
echo
