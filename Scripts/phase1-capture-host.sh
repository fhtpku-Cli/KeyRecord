#!/bin/bash
# Registry-bound wrapper: only phase1-qa-cases.json hostCases.capture may invoke
# ["/bin/bash", "Scripts/phase1-capture-host.sh", "{manifest}", "{attempt}"].
# The runner supplies a read-only authorization manifest path and an owned, fresh
# attempt directory. Keep set -euo pipefail; accept exactly these two positional
# paths, never arbitrary commands, flags, or additional arguments.
set -euo pipefail
if [[ $# != 2 ]]; then
    printf '%s\n' 'outcome=FAIL code=usage'
    exit 1
fi
# Task 7 has not supplied a qualified lock adapter or authorized controller binding.
# Deliberately stop before reading the manifest, loading Capture, or creating a tap.
printf '%s\n' '{"outcome":"BLOCKED","code":"capture_qualification_unavailable","tapCreations":0,"controllerInvocations":0}'
exit 2
