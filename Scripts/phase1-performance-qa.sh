#!/bin/bash
set -euo pipefail
if [[ $# != 2 ]]; then
    printf '%s\n' 'outcome=FAIL code=usage'
    exit 1
fi
# No endorsed performance controller exists. Do not open untrusted manifests or sample a process.
printf '%s\n' '{"outcome":"BLOCKED","exitCode":2,"code":"authorizedPerformanceControllerMissing","isFailure":false,"samples":0,"controllerInvocations":0,"productLaunches":0,"liveReceipt":false,"required":{"manifest":"host.json","controller":"approved SHA256","architectures":["arm64","x86_64"],"warmupSeconds":60,"windowSeconds":600,"repeats":3}}'
exit 2
