#!/usr/bin/env bash
# Registry-bound: phase1-qa-cases.json Q18 invokes exactly
# ["bash", "Scripts/task18-qa.sh", "{attempt}", "happy"|"failure"].
# Signed-hosted XCUITest (App/KeyRecordAppUITests/Phase1FlowTests.swift, 7 flows) needs
# an authorized signing host and stalls under both xcodebuild test-manager and direct
# xcrun xctest on this machine (runner session never attaches; bounded probe recorded
# in the task 18 receipt). The executable assertions are the hostless, in-process
# KeyRecordAppTests.Phase1FlowHostlessTests driven through direct xctest below.
set -euo pipefail
attempt="$1"
scenario="$2"
case "$scenario" in
  happy)
    filters='KeyRecordAppTests.Phase1FlowHostlessTests/testHappyConsentRejectionStaysInactive,KeyRecordAppTests.Phase1FlowHostlessTests/testHappyConsentAcceptancePauseResume,KeyRecordAppTests.Phase1FlowHostlessTests/testHappyReopenPersistsCycle,KeyRecordAppTests.Phase1FlowHostlessTests/testHappyExclusionSelectionRevokesGateInstantly,KeyRecordAppTests.Phase1FlowHostlessTests/testHappyResetTwoStageConfirmationCancelCallsNothing,KeyRecordAppTests.Phase1FlowHostlessTests/testHappyDeleteDistinctFromResetReturnsToFreshConsent'
    ;;
  failure)
    filters='KeyRecordAppTests.Phase1FlowHostlessTests/testFailureLoginToggleRejectionShowsError,KeyRecordAppTests.Phase1FlowHostlessTests/testFailureAggregateHiddenWhileLocked,KeyRecordAppTests.Phase1FlowHostlessTests/testFailureResetConfirmUnavailableSurfacesNotice,KeyRecordAppTests.Phase1FlowHostlessTests/testFailureDialogCopyBilingualAndRetentionDistinct,KeyRecordAppTests.Phase1FlowHostlessTests/testReleaseFixtureIsolationIsDebugCompiledOnly'
    ;;
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
exec xcrun xctest -XCTest "$filters" "$attempt/build/ui/Build/Products/Debug/KeyRecordAppTests.xctest"
