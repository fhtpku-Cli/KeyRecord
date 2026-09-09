#!/usr/bin/env bash
# Install sudoers for SP-2 D4 (requires interactive sudo once).
set -euo pipefail
user="$(whoami)"
dest="/etc/sudoers.d/keyrecord-phase0-d4"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

cat >"$tmp" <<EOF
# KeyRecord Phase 0 SP-2 D4 — sleepWake live leg only
$user ALL=(ALL) NOPASSWD: /usr/bin/true
$user ALL=(ALL) NOPASSWD: /usr/bin/pmset sleepnow
EOF

echo "Will install $dest with:"
cat "$tmp"
echo
read -r -p "Continue? [y/N] " ans
case "$ans" in
  y|Y|yes|YES) ;;
  *) echo "Aborted."; exit 1 ;;
esac

sudo install -m 440 -o root -g wheel "$tmp" "$dest"
sudo visudo -cf "$dest"
echo "Installed. Verifying sudo -n ..."
sudo -n true && echo "D4 sudo -n: OK" || { echo "D4 sudo -n: FAILED" >&2; exit 1; }
echo "Done. Run: KEYRECORD_ENABLE_D4=1 bash Spikes/Scripts/open-g0-sp2-live-terminal.sh"
