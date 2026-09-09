#!/usr/bin/env bash
# 在可见的 Terminal.app 窗口里启动 SP-2 live（不要从 Cursor 后台终端直接跑）。
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOG="/tmp/keyrecord-g0-sp2-live.log"
LAUNCH="$REPO_ROOT/Spikes/Scripts/.g0-sp2-live-launch.sh"

cat >"$LAUNCH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd '$REPO_ROOT'
exec bash Spikes/Scripts/run-g0-sp2-live.sh 2>&1 | tee '$LOG'
EOF
chmod +x "$LAUNCH"

/usr/bin/osascript -e 'tell application "Terminal" to activate' \
  -e "tell application \"Terminal\" to do script \"$LAUNCH\""

echo "已在新的 Terminal.app 窗口启动 SP-2 live。"
echo "请看：1) 弹出的 Terminal 窗口  2) 屏幕右上角系统通知"
echo "日志：$LOG"
