#!/bin/bash
set -euo pipefail
if [[ $# != 2 ]]; then
    printf '%s\n' 'outcome=FAIL code=usage'
    exit 1
fi
# Task 7 has not supplied a qualified lock adapter or authorized controller binding.
# Deliberately stop before reading the manifest, loading Capture, or creating a tap.
printf '%s\n' '{"outcome":"BLOCKED","code":"capture_qualification_unavailable","tapCreations":0,"controllerInvocations":0}'
exit 2
