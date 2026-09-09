#!/usr/bin/env bash
# Check D3/D4 prerequisites for SP-2 live legs.
set -euo pipefail
helper="/usr/local/libexec/keyrecord-secure-input-status"
echo "=== SP-2 D3/D4 prerequisite check ==="
if [[ -x "$helper" ]]; then
  echo "D3 helper: installed ($("$helper" --once))"
else
  echo "D3 helper: MISSING (run: bash Spikes/Scripts/install-g0-host-tools.sh)"
fi
if sudo -n true 2>/dev/null; then
  echo "D4 sudo -n: OK"
  if sudo -n /usr/bin/pmset sleepnow --help >/dev/null 2>&1; then
    echo "D4 pmset: reachable"
  else
    echo "D4 pmset: sudo OK but pmset sleepnow may need sudoers entry"
    echo "  see Spikes/Scripts/sudoers-keyrecord-phase0-d4.example"
  fi
else
  echo "D4 sudo -n: NOT CONFIGURED"
  echo "  install sudoers or run: sudo visudo -f /etc/sudoers.d/keyrecord-phase0-d4"
  echo "  see Spikes/Scripts/sudoers-keyrecord-phase0-d4.example"
fi
