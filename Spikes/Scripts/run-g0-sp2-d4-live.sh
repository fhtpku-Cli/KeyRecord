#!/usr/bin/env bash
# Full SP-2 live with D4 enabled (Mac will sleep). Use open-g0-sp2-live-terminal.sh wrapper.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

if ! sudo -n true 2>/dev/null; then
  echo "D4 sudo -n not configured. Run this first:" >&2
  echo "  bash Spikes/Scripts/install-g0-d4-sudoers.sh" >&2
  exit 1
fi

export KEYRECORD_ENABLE_D4=1
exec bash Spikes/Scripts/run-g0-sp2-live.sh "$@"
