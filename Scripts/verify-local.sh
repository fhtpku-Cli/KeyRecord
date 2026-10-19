#!/usr/bin/env bash
# Ordinary development verification; this does not qualify a live capture host.
set -euo pipefail

build_only=false
firmware_app_tests=false
case "${1:-}" in
  --build-only) build_only=true ;;
  --firmware-app-tests) firmware_app_tests=true ;;
  --help|-h)
    echo 'Usage: Scripts/verify-local.sh [--build-only|--firmware-app-tests]'
    echo 'Runs SwiftPM tests and Release build, then unsigned universal Release App and native Debug test builds.'
    echo 'Default also runs hostless App XCTest. --build-only skips only App XCTest (for headless CI).'
    echo '--firmware-app-tests runs the offline firmware native suites instead of the full App suite.'
    exit 0 ;;
  '') ;;
  *) echo "Unknown argument: $1" >&2; exit 2 ;;
esac
if [[ "$#" -gt 1 ]]; then
  echo 'Expected at most one argument; use --help.' >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This workflow requires macOS and full Xcode with Swift 6.2 or newer.' >&2
  exit 2
fi
native_arch="$(uname -m)"
case "$native_arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $native_arch" >&2; exit 2 ;; esac
mkdir -p "$repo_root/.build/verification"
attempt="$(mktemp -d "$repo_root/.build/verification/run.XXXXXX")"
echo "Verification artifacts: $attempt"

swift test 2>&1 | tee "$attempt/swift-test.log"
ruby Scripts/test-release-package.rb 2>&1 | tee "$attempt/release-package.log"
bash Scripts/test-capture-harness-offline.sh "$(swift build --show-bin-path)/KeyRecordCaptureHarness" \
  2>&1 | tee "$attempt/capture-harness.log"
swift build -c release 2>&1 | tee "$attempt/swift-release.log"
xcodebuild -project KeyRecord.xcodeproj -scheme KeyRecordApp -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$attempt/release" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build \
  2>&1 | tee "$attempt/app-release.log"
xcodebuild -project KeyRecord.xcodeproj -scheme KeyRecordApp -configuration Debug \
  -destination "platform=macOS,arch=$native_arch" -derivedDataPath "$attempt/debug" \
  ARCHS="$native_arch" ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build-for-testing \
  2>&1 | tee "$attempt/app-debug.log"

release_app="$attempt/release/Build/Products/Release/KeyRecordApp.app"
ruby Scripts/release-boundary.rb project "$repo_root" 2>&1 | tee "$attempt/release-source.log"
ruby Scripts/release-boundary.rb bundle "$release_app" 2>&1 | tee "$attempt/release-bundle.log"
bash Scripts/audit-product-network.sh --reviewed-updates "$release_app/Contents/MacOS/KeyRecordApp" \
  2>&1 | tee "$attempt/release-network-static.log"
test_bundle="$attempt/debug/Build/Products/Debug/KeyRecordAppTests.xctest"
if [[ "$build_only" == true ]]; then
  echo 'Build-only verification completed. App XCTest and live-host qualification were not run.'
elif [[ "$firmware_app_tests" == true ]]; then
  T23_RELEASE_APP="$release_app" bash Scripts/test-firmware-native.sh "$test_bundle" "$attempt/qa" 2>&1 | tee "$attempt/app-tests.log"
  echo 'Firmware development verification completed. Live-host qualification was not run.'
else
  # Match the existing hostless runner and exclude inherited capture/debug opt-ins.
  env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    DEVELOPER_DIR="$(xcode-select -p)" \
    KEYRECORD_QA_OUTPUT_DIR="$attempt/qa" T23_RELEASE_APP="$release_app" \
    xcrun xctest "$test_bundle" 2>&1 | tee "$attempt/app-tests.log"
  echo 'Development verification completed. Live-host qualification was not run.'
fi
