#!/bin/bash
set -euo pipefail
if [[ $# != 2 ]]; then
    printf '%s\n' 'outcome=FAIL code=usage'
    exit 1
fi
printf '%s\n' '{"outcome":"BLOCKED","exitCode":2,"code":"authorizedPerformanceControllerMissing","isFailure":false,"samples":0,"controllerInvocations":0,"productLaunches":0,"liveReceipt":false,"required":{"manifest":"host.json","controller":"approved SHA256","architectures":["arm64"],"warmupSeconds":30,"windowSeconds":120,"repeats":1}}'
exit 2
