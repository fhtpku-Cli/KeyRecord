#!/usr/bin/env bash
# Ordinary development verification; this does not qualify a live capture host.
set -euo pipefail

build_only=false
case "${1:-}" in
  --build-only) build_only=true ;;
  --help|-h)
    echo 'Usage: Scripts/verify-local.sh [--build-only]'
    echo 'Runs SwiftPM tests and Release build, then unsigned universal Release App and native Debug test builds.'
    echo 'Default also runs hostless App XCTest. --build-only skips only App XCTest (for headless CI).'
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
test_bundle="$attempt/debug/Build/Products/Debug/KeyRecordAppTests.xctest"
if [[ "$build_only" == true ]]; then
  echo 'Build-only verification completed. App XCTest and live-host qualification were not run.'
else
  # Match the existing hostless runner and exclude inherited capture/debug opt-ins.
  env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    DEVELOPER_DIR="$(xcode-select -p)" \
    KEYRECORD_QA_OUTPUT_DIR="$attempt/qa" T23_RELEASE_APP="$release_app" \
    xcrun xctest "$test_bundle" 2>&1 | tee "$attempt/app-tests.log"
  echo 'Development verification completed. Live-host qualification was not run.'
fi
