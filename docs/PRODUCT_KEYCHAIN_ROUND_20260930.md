# Approved product Keychain backend round

## Result

On 2026-09-30 the owner approved one bounded, Keychain-only round against the
already signed source `25ef0f117f9ee5d61c66cc78928f31efe1baabbc`. The actual App
`LocalKeychainBackend`, compiled into the signed Debug probe, passed
`HostedProductKeychainBackendTests/testAuthorizedIsolatedProductKeychainLifecycle`.
The xcresult summary and exact test node both report one passed test, zero failed
tests and zero skipped tests. The test took 6.148 seconds; the controller took
10.327 seconds, exited zero and needed no forced termination. Its final process
check and a subsequent independent helper read found no probe instances.

The test created only its fresh `com.keyrecord.phase1.probe.*` service items. It
checked initial absence, key creation/readback, metadata creation and update,
exact version inventory, a new backend object's metadata read, accessibility
and synchronization attributes, deletion and absence. Every successfully created
item then received exact deletion and an absence check before the test returned.
The passing case therefore includes test-item cleanup. The private service record
is retained as evidence; its existence does not mean a Keychain item remains.
The source's normal path contains 24 Security operations; no independent runtime
syscall counter was collected, so this is not a measured call-count claim.

This establishes bounded unlocked CRUD through the actual backend on this host.
It does not establish process restart, key rotation, lock-state accessibility,
full product privacy/recovery, or a collecting Release. There was no installation,
input capture, permission change, lock/sleep action or ordinary statistics access.
The approval is consumed; there is no automatic repeat.

## Setup failure retained

The first controller invocation stopped before launch with
`scratchRootMismatch`, `keychainCalls=0`, `controllerCalls=0`. On this host,
Foundation's resolved path for the approved `/private/tmp/...` directory is
`/tmp/...`. The controller was corrected to use that representation of the same
physical directory and its own script, preserving all existing path/identity
checks. The original manifest remains `host.preflight-path-blocked.json`.
The corrected invocation made the first and only actual test launch under the
approval; neither the signed artifact nor the Security authorization was weakened.

## Artifacts and remaining warning

Artifacts remain under
`/private/tmp/keyrecord-product-keychain-signing-fixed-20260930`:

- `keychain-run.json`: controller outcome and exact source/test identity.
- `keychain-run.log`: selected-test execution and normal completion.
- `keychain.xcresult`: one actual passing test, no failure or skip.
- `host.json`, `keychain-approved.xctestrun`: the executed, scoped configuration.
- `product-keychain-service.txt`: exact generated service only, no key material.

`xcresulttool get test-results summary` and `test-results tests` were used to
inspect the result. Their first sandboxed invocation could not write Xcode's
TestReport cache; reading with the required filesystem access succeeded without
rerunning the test or accessing Keychain.

Xcode retained a runtime warning: "This method should not be called on the main
thread as it may lead to UI unresponsiveness." The test class is MainActor-isolated
and the live method directly performs synchronous signing inspection and attribute
reads. The follow-up source marks only this async live method `nonisolated`, so
these calls no longer inherit the class's main actor. This is a test-harness change,
not a product backend change. The signed passing artifact remains unchanged;
removal of the warning in a signed run is not yet observed and does not justify
repeating the just-completed round on its own.

The follow-up unsigned Debug test build passes. Direct hostless XCTest selected
15 cases: 14 offline cases passed and the live case deliberately skipped because
its opt-in was absent. No real Keychain round was repeated. Logs:
`/private/tmp/keyrecord-product-keychain-offmain-build.log` and
`/private/tmp/keyrecord-product-keychain-offmain-selected-tests.log`.
The initial hostless loader failure (missing host debug-library search path) and
the subsequent zero-test invocation (Xcode-style filter used with direct XCTest)
remain in `...-offmain-tests.log` and `...-offmain-tests-with-library.log`;
neither is counted as verification. The successful invocation uses the explicit
host library directory and direct XCTest's `Module.Class` selectors.
