#!/bin/bash
set -euo pipefail
if [[ $# != 2 ]]; then
    printf '%s\n' 'outcome=FAIL code=usage'
    exit 1
fi
# No authorized PID-attribution controller is integrated; do not read a manifest
# or start capture, filters, the product, or any network operation in this lane.
printf '%s\n' '{"outcome":"BLOCKED","code":"network_qualification_unavailable","packetCaptures":0,"filterInstallations":0,"controllerInvocations":0,"productLaunches":0,"networkOperations":0,"liveReceipt":false}'
exit 2
