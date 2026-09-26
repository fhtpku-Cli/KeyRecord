#!/bin/bash
# Sample one already-running process. This script does not launch KeyRecord,
# inject input, change sleep, or unlock the session.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
if [[ $# -lt 12 ]]; then
  echo "usage: $0 --pid PID --expect-path PATH --protocol exploratory|pausedMonitorCandidate|formalFRS2 --phase LABEL --warmup-seconds N --measure-seconds N --interval-seconds N --output FILE" >&2
  exit 2
fi
bin="$root/.build/out/Products/Debug/KeyRecordResourceSampler"
if [[ ! -x "$bin" ]]; then
  echo "sampler missing; build it with: swift build --product KeyRecordResourceSampler" >&2
  exit 2
fi
exec "$bin" "$@"
