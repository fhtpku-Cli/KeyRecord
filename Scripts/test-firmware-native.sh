#!/usr/bin/env bash
# Synthetic endpoints, temporary encrypted stores and native UI; no live devices.
set -euo pipefail
if [[ "$#" -ne 2 ]]; then
  echo 'Usage: test-firmware-native.sh <built App XCTest bundle> <QA output directory>' >&2
  exit 2
fi
selectors=(
  'KeyRecordAppTests.UpdatesTests'
  'KeyRecordAppTests.KarabinerMappingFlowTests'
  'KeyRecordAppTests.VIAImportFlowTests'
  'KeyRecordAppTests.ProductRecoveryQuitTests/testProductionCompositionUsesHostBackendDependenciesAndKeepsUnknownDevicesReadOnly'
  'KeyRecordAppTests.ProductRecoveryQuitTests/testQuitCleansTemporaryBehaviorRulesBeforeClosingProtectedStore'
)
mkdir -p "$2"
if [[ -n "${T23_RELEASE_APP:-}" ]]; then selectors+=('KeyRecordAppTests.ProductReleaseBoundaryTests'); fi
for selector in "${selectors[@]}"; do
  log="$2/${selector//\//-}.log"
  env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}" KEYRECORD_QA_OUTPUT_DIR="$2" T23_RELEASE_APP="${T23_RELEASE_APP:-}" \
    xcrun xctest -XCTest "$selector" "$1" 2>&1 | tee "$log"
  if ! grep -Eq 'Executed [1-9][0-9]* tests?, with 0 failures' "$log"; then
    echo "XCTest did not execute passing tests for $selector" >&2
    exit 1
  fi
done
