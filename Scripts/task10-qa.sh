#!/usr/bin/env bash
# Registry-bound: phase1-qa-cases.json Q10 invokes exactly
# ["bash", "Scripts/task10-qa.sh", "{attempt}", "happy"|"failure"].
# Only unsigned Xcode builds, architecture inspection, and direct XCTest run here.
set -euo pipefail
attempt="$1"
scenario="$2"
case "$scenario" in
  happy) filters='KeyRecordAppTests.AppProjectTests,KeyRecordAppTests.PrimitiveStateTests/testHappyStateSemantics,KeyRecordAppTests.PrimitiveStateTests/testHappyMatrix,KeyRecordAppTests.PrimitiveStateTests/testHappyLocalizedWindowTitle' ;;
  failure) filters='KeyRecordAppTests.PrimitiveStateTests/testFailureStressMatrix,KeyRecordAppTests.PrimitiveStateTests/testFailureEmptyLabel,KeyRecordAppTests.PrimitiveStateTests/testFailureReducedMotionPolicy' ;;
  *) exit 1 ;;
esac
if [[ "$scenario" == happy ]]; then
  xcodebuild -project KeyRecord.xcodeproj -scheme KeyRecordApp -configuration Release \
    -derivedDataPath "$attempt/build/app" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO build
  lipo -archs "$attempt/build/app/Build/Products/Release/KeyRecordApp.app/Contents/MacOS/KeyRecordApp"
fi
xcodebuild -project KeyRecord.xcodeproj -scheme KeyRecordApp \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$attempt/build/ui" \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build-for-testing
# Hostless XCTest bypasses the unavailable Xcode test-manager launch session, not assertions.
exec xcrun xctest -XCTest "$filters" "$attempt/build/ui/Build/Products/Debug/KeyRecordAppTests.xctest"
