# T19 final verification

- Lane: `KeyRecord-wt-t19`, branch `feat/phase1-t19-composition`.
- Baseline: `273db0e`; verified code/registry: `debdd49`.
- Final attempt: `t19-attempt-20260913T173159Z`.
- Earlier `t19-attempt-20260913T164533Z` logs/receipts are retained as intermediate evidence, not the final acceptance result.

## Results

| Check | Result | Evidence |
| --- | --- | --- |
| Q19 happy, original runner | PASS, 11 executed, 0 skipped, 0 failed | `task-19/happy/assertion-summary.json` |
| Q19 failure, original runner | PASS, 15 executed, 0 skipped, 0 failed | `task-19/failure/assertion-summary.json` |
| FULL root XCTest | 336 executed, 0 skipped, 0 failed, 0 unexpected | `full-root.log` |
| Root Release warnings-as-errors | Build complete | `release-wae.log` |
| Unsigned Release App | BUILD SUCCEEDED | `app-build-unsigned.log` |

The baseline had 310 root tests; this lane adds 26. The Swift Testing footer with zero tests is not the XCTest suite count.

An additional whole-Xcode-graph `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` experiment failed because Xcode also adds `-suppress-warnings` to local-package dependencies. `app-build.log` preserves that rejected flag combination. The requested root Release WAE independently passes, and the normal unsigned App build passes. Xcode's AppIntents metadata-extraction warning is not a Swift compiler diagnostic. No standalone LSP diagnostics tool was available; Swift 6 compilation and the full test build supplied compiler diagnostics.

## Behavioral evidence and limits

- `Phase1IntegrationTests`: memory events through the real CaptureQueue gate/normalizer and AggregationReducer, real encrypted filesystem shards, store close/reopen. Two committed bare-key counts restore as two; a third unflushed count is lost. A delayed timer coalesces to one physical write.
- `Phase1QueuedProtectionTests`: deterministic suspended key retrieval crosses lock/reopen. Existing ciphertext remains byte-for-byte unchanged for the revoked queued writer; the revoked reader cannot return plaintext.
- `Phase1PersistenceRaceTests`: lock while ciphertext I/O is issued cannot publish a new readable manifest; no subsequent manifest write is issued. A five-second flush deadline returns timedOut without launching a second physical writer. Every reopen revokes the previous generation.
- `Phase1MaintenanceTests`: one shared FIFO serializes preferences and aggregate writes; a hung writer cannot falsely satisfy the maintenance drain; filesystem deletion cannot be followed by a suspended writer recreating files; reset reloads fresh preferences and restores collecting/paused expectation without regressing the cycle ID.
- `Phase1ReleaseIsolationTests`: actual Release compiler probe cannot reference the DEBUG fixture composition; product sources contain no scanned shell/network client APIs; product composition does not select ports using environment or command-line values.
- App composition uses the system event-source factory, system foreground/secure-input providers, ObjectStore, KeychainKeyring, lifecycle/reducers, the real login backend factory, and reset/deletion adapters. No live qualification is manufactured: UnqualifiedCapture and BlockedLiveKeychain remain the explicit T7 fail-closed boundaries. Capture/read paths remain disabled without qualified lock evidence. UI startup is compiled, not claimed as a signed hosted runtime pass.
- No real tap, real Keychain, login-item registration, network activity, or signed/hosted App execution was used by this verification. Hosted runtime validation remains T23; no T7 receipt is created by these tests.
- A one-second target is a scheduling cadence, not a durable-latency or loss-window guarantee. Already-issued ciphertext-only fsync/rename can finish after lock; no protected readable publication may cross the generation fence. Swift/Data copies are not claimed to be zeroized. All deltas since the last durable commit may be lost. Existing same-locator object replacement retains the contract's single-file rename durability semantics.

## Reproduction

Run from the lane with a new absolute attempt path (runner receipts are exclusive-create):

```sh
bash Scripts/phase1-qa.sh task 19 happy --attempt "$A"
bash Scripts/phase1-qa.sh task 19 failure --attempt "$A"
swift test --scratch-path "$A/build/root"
swift build -c release --scratch-path "$A/build/root" -Xswiftc -warnings-as-errors
xcodebuild -project KeyRecord.xcodeproj -scheme KeyRecordApp -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$A/app-build" \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 build
```

All executed commands were bounded below eight minutes. Compilation caches and test-scratch directories were removed after verification; receipts and logs remain. Runner/Spikes semantics and historical repository evidence were not changed. No push or `.omo/push` action occurred.

## Incremental commits

1. `ea6e49e` flush cadence reducer
2. `7765e6d` explicit async flush completion
3. `83f6ca8` fenced ObjectStore persistence/reads
4. `4a8e190` reopen revocation and timed-out writer ownership
5. `ef109aa` aggregate encrypted recovery integration
6. `3b0be43` lock/slow writer tests
7. `77b3455` real App composition behind qualification
8. `4815a2b` delayed protected-completion tests
9. `11f00d8` login backend symbol isolation
10. `b92dbbf` shared serial writer and bounded maintenance drain
11. `a9934df` fresh lifecycle reload and maintenance regressions
12. `73f0507` App maintenance wiring and contract root
13. `debdd49` Q19 registry

This evidence-only commit follows the verified code/registry commits.
