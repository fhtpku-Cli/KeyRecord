# Synthetic live-permission recovery coverage

Product source: main `64590a0e9b57a55af9a23921983f2c16bb59c62e`.
This follow-up adds only `testLivePermissionRevocationRequiresExplicitStartAndPreservesDurableCounts`
to `App/KeyRecordAppTests/ProductRecoveryQuitTests.swift`; no product behavior changed.

The real product composition runs against the existing synthetic host, tap, memory
Keychain and temporary encrypted store. The test:

1. Collects two bare-key counts and waits for the normal pulse to write them, without explicit flush.
2. Denies the fake permission and emits `permissionRevoked` through the source invalidation callback.
3. Waits for blocked lifecycle, no live capture, closed key gate and hidden sensitive content;
   an attempted press through the stopped tap returns closed and aggregate delta stays unchanged.
4. Tries Start while still denied and verifies capture remains closed.
5. Grants the fake permission and observes 600 ms without automatic restart or visible sensitive content.
6. Explicitly starts, verifies a live collecting session and changed queue generation,
   reads the retained disk count of two, adds one input, and waits for the normal pulse to persist three.
7. Quits through the product action and verifies one termination request.

This covers downstream product response to a delivered invalidation. It does not
prove that macOS emits that invalidation on actual permission revocation, establish
a maximum closure time, prove indefinite no-auto-restart, or determine whether
real regrant requires an application relaunch. It uses no real system permission,
global event tap or real Keychain. The stopped-tap check is not a delayed old-generation
callback injection. Existing generation-boundary tests retain their separate scope.

No real host round or additional performance measurement is required to run this test.
PR #11 remains a separate documentation/evidence change.

## Validation on 2026-09-27

- Native arm64 Debug `build-for-testing`, unsigned: passed.
- New case alone: 1 test, 0 failures (2.842 seconds).
- Entire `ProductRecoveryQuitTests` in one process: 45 tests, 0 failures (57.747 seconds).
- `git diff --check`: passed.

Logs remain locally under `.build/permission-evidence/`; no raw test store or key
material is part of this change. No SwiftPM targets or Release product code changed,
so their prior checks are not relabeled as freshly executed for this test-only change.
