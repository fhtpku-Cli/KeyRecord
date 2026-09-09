#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAUNCH="$REPO_ROOT/Spikes/Scripts/.g0-d4-live-launch.sh"

if ! sudo -n true 2>/dev/null; then
  cat >"$LAUNCH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd $(printf '%q' "$REPO_ROOT")
echo "=== Step 1: install D4 sudoers (needs your password once) ==="
bash Spikes/Scripts/install-g0-d4-sudoers.sh
echo
echo "=== Step 2: verify ==="
bash Spikes/Scripts/check-g0-sp2-d34-prereqs.sh
echo
read -r -p "Press Enter to start D4 live run (Mac WILL sleep)… "
KEYRECORD_ENABLE_D4=1 bash Spikes/Scripts/run-g0-sp2-live.sh
EOF
else
  cat >"$LAUNCH" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd $(printf '%q' "$REPO_ROOT")
bash Spikes/Scripts/check-g0-sp2-d34-prereqs.sh
echo
echo "WARNING: After window 5 this Mac will SLEEP. Save all work."
read -r -p "Press Enter to start D4 live run… "
KEYRECORD_ENABLE_D4=1 bash Spikes/Scripts/run-g0-sp2-live.sh
EOF
fi
chmod +x "$LAUNCH"

/usr/bin/osascript -e 'tell application "Terminal" to activate' \
  -e "tell application \"Terminal\" to do script \"$LAUNCH\""

echo "Opened Terminal for D4 setup/live."
