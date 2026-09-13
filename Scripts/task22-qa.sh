#!/usr/bin/env bash
# Registry-bound: phase1-qa-cases.json Q22 invokes exactly
# ["bash", "Scripts/task22-qa.sh", "{attempt}", "happy"|"failure"].
# In-process Window Server/AX XCTest; signed Full Keyboard Access, VoiceOver,
# system accessibility toggles and native menu screen edges remain T23.
set -euo pipefail
[[ "$#" -eq 2 ]] || exit 1
attempt="$1"
scenario="$2"
case "$scenario" in
  happy)
    filters='KeyRecordAppTests.ScreenMatrixTests,KeyRecordAppTests.T22AccessibilityTests,KeyRecordAppTests.T22AppearanceTests,KeyRecordAppTests.Phase1FlowHostlessTests'
    ;;
  failure)
    filters='KeyRecordAppTests.ScreenStressTests'
    ;;
  *) exit 1 ;;
esac
xcodebuild -project KeyRecord.xcodeproj -scheme KeyRecordApp \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$attempt/build/app" \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build-for-testing
exec xcrun xctest -XCTest "$filters" "$attempt/build/app/Build/Products/Debug/KeyRecordAppTests.xctest"
