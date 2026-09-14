#!/usr/bin/env bash
# Registry-bound Q6: unsigned build + SPM logic tests.
# Signed hosted execution is task 7.
set -euo pipefail
case "${1:-}" in
  happy)
    xcodebuild -project Spikes/KeychainLifecycle/KeychainLifecycle.xcodeproj \
      -scheme KeychainLifecycleProbe -destination 'platform=macOS' \
      -derivedDataPath "$2/build/lifecycle" CODE_SIGNING_ALLOWED=NO build
    exec swift test --package-path Spikes/KeychainLifecycle --scratch-path "$2/build/preflight"
    ;;
  failure)
    exec swift test --package-path Spikes/KeychainLifecycle --scratch-path "$2/build/preflight" --filter 'testFailure|HostedProbePreflightTests/test(Expired|HostIDMismatch|ArchitectureMismatch|MacOSMismatch|TeamIDMismatch|CertificateFingerprintMismatch|BundleIDsMismatch|EntitlementsMismatch|NamespaceMismatch|ScratchRootMismatch|AttemptMismatch|OperationAllowlistMismatch|Controller|UnavailableIdentity|MissingManifest|MalformedManifest)'
    ;;
  preflight)
    exec swift run --package-path Spikes/KeychainLifecycle --scratch-path "$3/build/preflight" lifecycle-preflight --manifest "$2" --attempt "$3"
    ;;
  *) exit 2 ;;
esac
