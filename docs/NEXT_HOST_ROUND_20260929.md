# Next owner-assisted round: collecting lock and explicit recovery

Preparation only, 2026-09-29. No new product process, permission toggle, Keychain
operation, lock/sleep action or long resource window ran during this preparation.
Wait for approval and an explicit ready response for this concrete round.

## Exact candidate and scope

- Installed App: `~/Applications/KeyRecord MVP Trial 20260929.app`.
- Signed product source: `8e3ca0c552697c2755f369fe420b47ee79612038`.
- Bundle and Keychain namespace: `com.keyrecord.trial.mvp20260929`.
- Existing private root: `/private/tmp/keyrecord-mvp-readiness-20260929`.
- Reuse only its isolated encrypted store; last reported shortcuts 7, bare keys 0.
- New output: `privacy-lock.jsonl` and `summary-lock.json`; retain all old rounds.
- Normal Quit at 175 seconds; force-stop only this exact instance at 180 seconds
  if normal Quit has not completed. An interrupted/no-summary result is not PASS.
- Only the owner locks and unlocks. No sleep, user switching, permission changes,
  packet capture, ordinary statistics access or new signing-account work.

This tests the collecting state. Paused-state lock and sleep/wake are separate
scenarios. The owner must be present throughout; the controller does not prevent
sleep, perform authentication, or keep the App running beyond the trial.

## Prepared local tools

`/private/tmp/keyrecord-mvp-profile-attempt-20260929/BoundedTrial.swift` and its
compiled `BoundedTrial` now support `--lock-check` / `--lock`. Both check the
existing root contents and exact trial identity before launch; a completed or
partial lock round prevents reuse of the same output paths. The signature and
isolation check passed without starting the App.

The read-only `PrivacyTrialReport` in that directory compiles with the current
`Tests/KeyRecordMeasurement/ResourceEvaluation.swift`; it reads only the coarse
journal and summary, not encrypted store contents or keys. Against the earlier
interrupted permission round it correctly returns `interval-not-ended`, with
continuous/rendering/every-read claims false.

Compile command for the controller:

```sh
xcrun swiftc -swift-version 6 -parse-as-library -framework AppKit \
  -module-cache-path /private/tmp/keyrecord-mvp-controller-module-cache \
  /private/tmp/keyrecord-mvp-profile-attempt-20260929/BoundedTrial.swift \
  -o /private/tmp/keyrecord-mvp-profile-attempt-20260929/BoundedTrial
```

The actual Swift 6 compiler passed. Standalone SourceKit does not know this
`-parse-as-library` invocation and reports an unrelated `@main` mode diagnostic.

## Operator sequence after readiness

1. Launch once with the prepared `--lock` mode and explicit isolation. Observe
   Collecting and granted Input Monitoring before requesting any owner action.
2. Ask the owner to press one Command-A in blank TextEdit. Wait for the count and
   successful save; do not infer exact attribution from the aggregate alone.
3. Ask the owner to lock for about 30 seconds, then unlock normally. During this
   interval require live locked observations, closed capture and hidden state.
   Never ask the owner to return to chat or disclose credentials while locked.
4. After unlock, wait at least five seconds without Start. Require a fresh
   unlocked observation while capture remains closed. If it automatically
   collects or an unexpected permission/Keychain prompt appears, stop normally.
5. Only after the previous observation, ask the owner to select Start/Retry in
   the blocked trial. Observe the explicit-start action, fresh readiness and
   Collecting, then request one more Command-A in blank TextEdit.
6. Request normal Quit early once enough evidence exists, otherwise the
   175-second controller deadline ends the round. Verify the exit action,
   summary and absence of the exact process. Do not repeat a failed round.

If the owner has not confirmed the next action in time, allow the bounded round
to end. Never add input, silently extend it, or relaunch to obtain a PASS.

## Result interpretation

Require the product's `protectedStateClosed` begin, locked and later unlocked
observations, and the explicit `captureSessionStarting` end. Evaluate closed
interval deltas for aggregation, normalization, protected gate entries, reads
and publications; retained and new post-recovery counts must be distinguishable.
Preserve incomplete intervals and write failures as such. Cached summary
liveness is not an exit witness.

This is finite, non-atomic product observation. Even a clean result does not
prove continuous closure, every protected read, pixels, raw Keychain behavior
while locked, same-process permission regrant, or full hosted lifecycle support.
The hosted Keychain controller still needs a real product observer and authority;
its restart/session-handoff branches remain unavailable. Do not replace missing
observations with zero or a successful fake.

## Autonomous checks completed

- Latest PR #17 documentation head `12f2f9a35`: both CI jobs passed (7m12s and
  6m22s); the preceding signed product is still `8e3ca0c55`.
- `swift test --filter ResourceEvaluationTests`: 14 tests passed, zero failures.
  Log: `/private/tmp/keyrecord-next-round-measurement-tests-20260929.log`.
- `KeyRecordPerformanceTrial` and `KeyRecordResourceSampler` built successfully.
- Performance evaluator `--self-check-evaluation`: pass, synthetic=true,
  productPass=false. Sampler `--self-check`: measured synthetic process,
  recomputed=match, markerAligned=measured, not-a-product-pass.
- Swift compilation and `BoundedTrial --lock-check` passed. No launch occurred.

Performance remains separate: its controller accepts a dedicated performance
bundle/namespace and a fresh root per window. Today's MVP-trial check does not
qualify that package or authorize six live windows. The product's real permission
provider remains in the replay path. Intel and network capture are not part of
this next round.
