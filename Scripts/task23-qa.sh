#!/usr/bin/env bash
set -euo pipefail
[[ "$#" -eq 2 ]] || exit 1
attempt="$1"
case "$2" in
  happy) filters='KeyRecordAppTests.ProductReleaseBoundaryTests/testUnsignedUniversalBuildCapabilityIsNotSignatureEvidence,KeyRecordAppTests.ProductReleaseBoundaryTests/testReleaseProjectHasOneProductAndRestrictedCapabilities' ;;
  failure) filters='KeyRecordAppTests.ProductReleaseBoundaryTests' ;;
  *) exit 1 ;;
esac
# Unsigned compilation capability only: never launch this app as signing evidence.
xcodebuild -quiet -project KeyRecord.xcodeproj -scheme KeyRecordApp -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$attempt/build/release" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project KeyRecord.xcodeproj -scheme KeyRecordApp \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath "$attempt/build/app" \
  ARCHS="$(uname -m)" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build-for-testing
exec env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  T23_RELEASE_APP="$attempt/build/release/Build/Products/Release/KeyRecordApp.app" \
  xcrun xctest -XCTest "$filters" "$attempt/build/app/Build/Products/Debug/KeyRecordAppTests.xctest"
