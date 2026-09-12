#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  happy)
    xcodebuild -project Spikes/KeychainLifecycle/KeychainLifecycle.xcodeproj \
      -scheme KeychainLifecycleProbe -destination 'platform=macOS' \
      -derivedDataPath "$2/build/lifecycle" CODE_SIGNING_ALLOWED=NO build
    exec xcodebuild -project Spikes/KeychainLifecycle/KeychainLifecycle.xcodeproj \
      -scheme KeychainLifecycleProbe -destination 'platform=macOS' \
      -derivedDataPath "$2/build/lifecycle" CODE_SIGNING_ALLOWED=NO test
    ;;
  failure)
    exec swift test --package-path Spikes/KeychainLifecycle --scratch-path "$2/build/preflight" --filter HostedProbePreflightTests/testFailure
    ;;
  preflight)
    exec swift run --package-path Spikes/KeychainLifecycle --scratch-path "$3/build/preflight" lifecycle-preflight --manifest "$2" --attempt "$3"
    ;;
  *) exit 2 ;;
esac
