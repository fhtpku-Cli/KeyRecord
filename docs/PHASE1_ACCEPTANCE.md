# Phase 1 remaining acceptance

Current status: [PROJECT_STATUS.md](PROJECT_STATUS.md). Requirements: [PHASE1_CONTRACT.md](PHASE1_CONTRACT.md) and architecture §12.4/15. This matrix separates executable regression coverage from host qualification; it is not a new gate or acceptance receipt.

## Evidence and remaining work

Current-main update: PR #13 merged at `6257b03b40f618fd976c6cbcc77dc83d374c59bb`. Marked Debug trials now reject missing isolation configuration on relaunch. The [bounded permission restart observation](PERMISSION_RECOVERY_TEST.md) preserves counts and normal Quit, but does not close same-process revoke/regrant coverage. PR #10 Secure Input evidence remains historical in [its report](PR10_SINGLEPAGE_REGRESSION.md); formal Phase 1 acceptance remains open.

Historical follow-up: PR5/6/7 were merged at `3b9345c30086e9e33c4510047e2692337f5b8643`. The subsequent paused-restoration repair completed its bounded owner-assisted rounds; see [the acceptance record and remaining scope](CURRENT_MAIN_ACCEPTANCE.md). The starting source and measurements below describe the earlier offline closeout, not fresh current-main qualification.

Starting source: `31b65c523db3ec40c06f0877395da52b7c026935` (merged PR #3/#4). Earlier roadmap audit reports 480 package tests and main CI 35643672591 successful at that source. Those are historical measurements, not a fresh run in this worktree. New measurements are recorded in the closeout report linked from current status.

| Requirement | Evidence / version | Gap | Safe autonomous work | Human / host prerequisite |
|---|---|---|---|---|
| FR-C normalization, sided modifiers, repeats, event origin | Package Core/Capture regressions; older signed Debug counted bounded TextEdit input | Current signed candidate, keyboard/OS coverage; unknown first modifier side is supported | Queue, normalization and synthetic provenance tests | On identified current Debug candidate, release modifiers then press a small agreed shortcut set; compare all matching rows |
| FR-P privacy gate and zero metadata while closed | Synthetic privacy, overflow/generation, queued protection tests; bounded Secure Input closure/recovery on `64590a0e` ([report](PR10_SINGLEPAGE_REGRESSION.md)); older exclusion observation | Synthetic product permission revoke/explicit recovery is covered ([test](PERMISSION_RECOVERY_TEST.md)); actual OS permission delivery, broader continuous/hardware coverage and user switching remain open; one Debug Secure Input round is not full qualification | Inject false/unknown conditions with nonzero pending events; assert zero deltas and stale completions discarded | Separately approved short trials with coarse state/counters only, known permitted input before/after; no password text or per-event stream |
| Lock/sleep, user pause, recovery | Older signed Debug observed manual Start after lock and actual sleep | Not continuous locked-interval proof; current binary and OS support not qualified | Lifecycle/restart/flush race tests with delayed writes and synthetic lock providers | Owner operates lock/sleep; record closed state, retained durable counts, fresh-check recovery and paused-state behavior; no automatic unlock/wake |
| Encrypted persistence, missing key, corruption, reset/delete | Real temporary-file AES-GCM, crash subprocess, rotation/reset/recovery tests with injected keys | Real Keychain accessibility and current-candidate lifecycle qualification | Replay existing Store/Integration regressions, canary/serialization scans | Isolated explicitly approved test namespace and authorized controller; never remove user keys or use real statistics as fixtures |
| FR-P1 data stays on device | Product source scan and binary audit tooling have positive and negative fixture coverage; the unsigned universal Release executable from product source `648144555b0bee70b819148f381de1d6aacbb54c` passed the static audit ([privacy checks](PRIVACY_BOUNDARIES.md)) | Repeat the binary audit on the exact signed Release candidate when it exists. Prior packet observations remain invalid historical records | Use existing `PrivacyEgressTests` and `audit-product-network.sh`; review any future update checker separately | No packet-capture round is required |
| FR-S2 CPU / memory | Compressed XCTest probe; Debug-only fixed replay now reaches the product reducer and encrypted store in a hostless test; one earlier signed Debug ARM paused and one collecting-idle window of about 600 seconds each ([dated results](POSTMERGE_VERIFY_20260926.md#resource-measurement--2026-09-26-2146-and-2217)) | An approved product measurement controller and three typing/idle repetitions on native ARM and Intel remain open; earlier single-run windows and hostless replay do not qualify current main | Keep the replay fixture matched to the existing receipt, verify the bounded product path and measurement arithmetic | Full §12.4 protocol below when actually pursuing qualification; actual Intel hardware, no Rosetta substitution |
| Native UI / accessibility / consent / locales | Prior App XCTest and bounded screenshots at explicitly older revisions | Current-candidate manual flow, VoiceOver, appearance coverage | Build native Debug tests and universal Release; run only hostless tests known not to show windows while owner rests | Logged-in owner for UI/VoiceOver flow; window tests deferred while unattended |
| Release restrictions / distribution | Release uses BlockedLiveKeychain and UnqualifiedCapture | Signed qualification, notarization and release-specific checks | Compile both architectures and scan Release boundary; preserve blocks | Signing identity and explicit release operation scope; G1 alone is not public release approval |

The local historical evidence remains read-only in the primary checkout under `.omo/repair-20260921/` and `.omo/repair-20260922/{modifier-investigation,roadmap-review}/`. Earlier live trials used a signed Debug candidate before merged main's diagnostic-path change. They are not current-main or Release qualification. See current status for the precise partial lock trial and durable-counter limitations.

The hosted Keychain scenario controller requires a separate product observation
for lock-transition results. Without it, those steps return BLOCKED; the fake
observer in offline tests establishes only that the controller handles supplied
measurements. No live product observer is wired into the hosted probe yet.
The Debug privacy journal records capture state, aggregate counters, protected
snapshot/analysis attempts, and successful snapshot/analysis assignments at the
flow boundary. These assignments do not prove screen rendering. Protected-data
reads outside those paths are still not counted exhaustively, and no product
observer is connected to the hosted controller. The journal cannot supply its
`protectedReadDelta` or `publishDelta`; absent values must not be projected as
zero. The hosted scenario report now leaves those deltas absent when no product
observation was made and blocks a lock-transition PASS if any required delta is
missing. Older journal lines without `analysisPublicationCount` yield an
inconclusive closed-interval evaluation. Finite interval samples also do not
prove that capture stayed closed at every instant of a lock.
The sleep/wake scenario now has separate `sleepClosed` and `wakeRevalidate`
steps. The previous composite step could accept one post-wake observation
without ever checking that capture closed during sleep. A failing-first offline
test reproduced that gap; the revised runner stops before wake when the sleep
closure observation or independent locked witness is missing. The old composite
step remains decodable but cannot pass. The complete offline package suite and
unsigned hosted Xcode test bundle build passed. This is scenario-model coverage
only: there is still no live lock authority or product observer attached to the
hosted test App.
The hosted product-observation type now retains missing counters as absent
values. A missing capture-closed observation on a lock step now yields BLOCKED
instead of FAIL; an observed still-open capture remains FAIL. The missing-capture
test failed before this repair and passed afterward. Both offline
KeychainLifecycle test bundles passed 28/28 and 82/82, and the unsigned hosted
Xcode test bundle compiled. No product observer or real Keychain operation was
added by this classification repair.
The hosted controller now checks its authority preflight for every lock
transition and requests a fresh unlocked witness for the delete/missing read;
loss of that witness blocks the step before another Keychain operation. This is
offline controller behavior, not a qualified system lock observation.
The scenario report also rejects a claimed CRUD, delete/missing read, or cleanup
PASS when its recorded Keychain call count does not match the operations that
step must have executed; a zero-call fake cannot qualify those steps.
The hosted controller now reports the backend's actual per-step call-count
change even when a later operation throws. Before this repair, add followed by
an interrupted read yielded a blocked step claiming zero Keychain calls, while
the cleanup call was still counted. A failing reproduction and follow-up tests
cover interrupted CRUD, delete/missing read and cleanup. The full offline
KeychainLifecycle package test suite and unsigned hosted test compilation
passed. No real Keychain item or lock transition was exercised by this repair.
The probe's signed effect request and the current armed Debug product both select
the nonsynchronizable data-protection Keychain (`kSecUseDataProtectionKeychain`,
SDK key `nleg`) so that `WhenUnlockedThisDeviceOnly` can apply. The earlier Debug
product used the traditional file Keychain, where macOS does not apply that
accessibility attribute. An unavailable data-protection Keychain now blocks
product bootstrap without falling back. Query construction tests do not perform
real Keychain operations. A successful probe result still cannot establish that
the product's own backend closed or reopened correctly across lock transitions;
that requires an isolated product run with product observation.
An opt-in hosted XCTest now compiles a real, exact-namespace data-protection
Keychain add/read/attributes/delete/read-after-delete path. It requires an
explicit run switch and a valid signed host manifest whose only permitted
operation is Keychain. The test retains the exact service in the private
attempt directory for cleanup
if a later step fails. It has only built unsigned; no real Keychain operation
has run. It can establish isolated CRUD behavior, not product lock lifecycle.
An offline product regression models an existing encrypted store after its old
Keychain namespace becomes unavailable: relaunch stays out of Collecting, creates
no replacement key and leaves the encrypted manifest unchanged. It does not
establish real macOS Keychain access or migrate earlier trial data.
The collecting monitor now also reads the session-lock provider on each 250 ms
poll. A locked or unknown result revokes capture, closes protected state and
requires an explicit Start after an unlocked read. A hostless product test omits
the lock notification and checks both results, including no automatic recovery.
The interval is a polling cadence, not a guaranteed real-macOS closure time;
actual lock/sleep delivery and continuous closed-state evidence remain open.

The Debug distributed screen-lock callback now revokes the key gate, capture queue,
and manual recovery fence synchronously, before scheduling main-actor lifecycle
cleanup. A hostless product test failed on the previous implementation: directly
after a delivered lock notification, the gate and queue were still open and a
synthetic event was accepted. The same test now observes the gate and queue
closed and the event rejected before the callback returns. The unsigned Debug
App test bundle compiled; two logged runs of all 53 product recovery tests
passed. An earlier full run reported
three failures with its diagnostic lines lost to console truncation; the two
logged reruns did not reproduce them. This proves the local callback ordering,
not delivery timing or protected-state closure on a real macOS lock.

## Executable lanes and their meaning

- `Scripts/verify-local.sh --build-only`: package tests, offline harness CLI regressions, SwiftPM Release, universal unsigned App Release and native Debug test compilation. Does not launch capture or run App XCTest. A completed build is not Intel execution.
- `swift test --filter 'Phase1|Privacy|Keyring|CycleReset|Rotation|Flush|Lifecycle|Capture'`: focused synthetic regressions; use the full suite for final package coverage. Build directories are per checkout; do not run concurrent SwiftPM jobs in the same checkout.
- `swift test --filter PerformanceDriverTests`: short in-process synthetic queue → reducer → encrypted temporary store probe. It uses fixture keys, never Keychain or an event tap. Inspect both `PERFORMANCE_RECEIPT` and `PERFORMANCE_BUDGET`; a green XCTest only means the measurement/assertions ran, not that budget passed.
- `Scripts/audit-product-network.sh <Release Mach-O executable>`: static capability scan of the exact Release executable being qualified, with linked-socket negative fixture. Debug's main binary is only a loader; it cannot alone represent the Debug dylib. The result is a capability audit, not a measured zero-packet claim.
- `Scripts/phase1-qa.sh host <capture|sp6a|performance|signed-build> --manifest <approved-host.json> --attempt <fresh-absolute-repo-directory>`: active host qualification modes. The historical `network` mode remains registered but BLOCKED and is no longer a FR-P1 prerequisite. The shipped unavailable controllers deliberately return BLOCKED; a made-up manifest cannot grant authorization or make a controller exist.
- The revised `KeyRecordCaptureHarness --mode offline` exercises in-memory Core fixtures only. `--help` and no arguments show help; physical/synthetic modes now return BLOCKED before any host adapter is created. Run `bash Scripts/test-capture-harness-offline.sh <path-to-revised-binary>` for CLI regressions. Do not run that script against an older binary: the historical harness's `--help` started live capture and its `synthetic` mode posted OS events. The old live implementation lacked continuous privacy checks and has been retired; Git preserves it as historical evidence. This tool does not qualify the product pipeline.

## Performance plan

1. Identify the product build, native architecture, macOS, machine model/chip/RAM and exact workload. The single-window trial report records those host fields, the loader digest and the actual `KeyRecordApp.debug.dylib` code digest; its sampler archive retains the raw resource samples. The controller checks both files before and after a window, and the six-window evaluator requires matching code digests. An older report without the code digest is invalid. Keep workload reproducible in source. The Debug-only fixed replay uses the same fixture bytes as `PerformanceReceipt.workload`; the existing compressed XCTest measurement remains a component probe.
2. Use a dedicated approved test store and injected/test keys for isolated component measurement. A host product replay instead uses the real local data-protection Keychain backend with a dedicated trial namespace and store; running it requires approval for those real Keychain operations. The candidate Debug product replay bypasses the system event tap, uses a fixed foreground, and posts no events to other applications. Source wiring retains the collecting-state monitor, including its session-lock, Input Monitoring and Secure Input polls, in the sampled App process; a real replay measurement would include their CPU cost but still omit system event-tap cost. Its typing or idle mode waits up to 120 seconds for Collecting, runs 6,600 workload ticks over 660 seconds followed by a two-second drain tail when uninterrupted, and records a private work summary with a shared monotonic start time. The tail is outside the 60-second warmup and 600-second measured window. Before reading the trial's encrypted aggregate, the product checks that its queue drained and the reduced total matches accepted workload events; a mismatch invalidates the window. `KeyRecordPerformanceTrial` prepares one isolated LaunchServices run and pairs it with `KeyRecordResourceSampler`; the controller and a dedicated trial App have passed offline build and no-launch inspection, but have not run on a product host. Its offline `--evaluate --session <private-root>` mode expects six completed private subdirectories named `typing-1` through `typing-3` and `idle-1` through `idle-3`; it rereads and recomputes each raw archive, requires matching candidate and host identity, and reports strict per-host budgets. It does not launch an App or establish Phase 1 qualification. The six-window ARM/Intel launch procedure, owner approval and real measurements remain open; `phase1-performance-qa.sh` remains BLOCKED.
3. On **each** native ARM and Intel reference host, run 60 seconds warmup, 600 seconds typing and 600 seconds idle measurement, repeated three times in six separate App launches. The evaluator reads each archive's PID and process start time and rejects reused process windows; copying one result into another repeat cannot establish qualification. Schedule while the owner is available. Never prevent sleep; if sleep or session loss interrupts a window, retain it as interrupted and rerun later with approval.
4. CPU = process CPU seconds / elapsed monotonic seconds × 100, relative to one logical core. Formal windows require an observed sample at or after the full 600-second endpoint; a near-endpoint sample below 600 seconds remains interrupted. Report typing and idle medians separately. Typing <1%, idle <0.1%. Record physical footprint across both measured phases at a stated cadence, their means and peaks; each phase must stay below 100 MB. Sampled peak is not proof no inter-sample transient occurred. Do not substitute RSS, whole-machine CPU or a ten-minute wall clock dominated by sleep.
5. Keep raw samples, measured duration and work completed. Report controller/fixture overhead explicitly; do not subtract an arbitrary baseline or turn an XCTest failure into a product regression claim. Empty/missing/interrupted evidence is not PASS. Compare input and durable aggregate totals to ensure the workload really ran.

Candidate review found that fixed replay had used a constant-granted Input
Monitoring stub, so a formal product replay would not include the real system
preflight cost. The App now supplies `SystemInputMonitoringPermission` to the
replay source. Replay requires authorization before Collecting and keeps the
same preflight in its collecting-state monitor; only hostless tests inject a
synthetic permission provider. Two focused replay tests, including denial, and
an unsigned Debug App test build passed. No host replay was run after this change.

The private native ARM Debug trial package prepared from this PR has bundle ID
`com.keyrecord.trial.performance5c54a178`, a distinct display name and the
required isolation marker. Its ad-hoc signature passed strict verification.
The loader digest is `9e4aa08ea71d55e2cc6e651ff59ec40152e9df848f141cf6d80aaaaf41d69480`;
the actual Debug code digest is `86babf978c04e9955cd1e5f9e3dfaf90f4756ead20dd178f3a3d354a7b88f559`.
The controller's `--check` accepted those exact files without launching the
App. The sampler and six-window evaluator passed synthetic self-checks only;
there are no product resource samples or Keychain effects from this preparation.

That first package predates the later candidate and its product-code digest does
not match. A second native ARM Debug package was built from source commit
`df6163f85896a7d906bc7c99b026b496e16328e1` at
`/private/tmp/keyrecord-performance-current-df6163f8/DerivedData/Build/Products/Debug/KeyRecordApp.app`.
It uses bundle ID `com.keyrecord.trial.performance.df6163f8`, the dedicated
Performance Trial display name, and the required isolation marker. Its ad-hoc
signature passed strict deep verification. The loader SHA-256 is
`63ebbad86770d099762db652f3157a59de72b223d026a964f991c6fc05276cd2`;
the actual Debug product-code SHA-256 is
`94245b8df2a0e6bbefe7ca7adee379bbe70052d0209560d2106af3948a1aae39`.
The controller's `--check` accepted this package and reported `launched=false`.
The current sampler's offline self-check reported `measured` with recomputation
and marker alignment matching; the six-window evaluator's synthetic self-check
also passed. No performance window, product Keychain operation, or qualification
measurement was performed with this package.

That earlier `--check` only verified the ad hoc code signature. The performance
replay subsequently needs the product's data-protection Keychain, and the
permission witness trial showed that a valid code signature alone can still
lead to Keychain status `-34018`. The controller now requires a matching
embedded provisioning profile and signed application identifier before it
reports a trial package ready. Rechecking the second package above returned
`trial-provisioning-profile-missing` with exit 2 and did not launch it. This
preflight prevents a known unusable package from consuming a formal window;
it does not prove that a future package can access the Keychain at runtime.

The subsequent cycle-reset repair at `648144555b0bee70b819148f381de1d6aacbb54c`
changed the product code again. An unsigned Debug build of that source has
`KeyRecordApp.debug.dylib` SHA-256
`4579f6a27b9df613190a7027f0c08d5a796750226f4f078439f3ea697893fd60`,
which differs from both prepared trial packages. They remain no-launch historical
preparations, not a measurement package for the revised source. Prepare a matching
isolated package only for an approved real performance session.

An offline resource-evaluator reproduction showed that a sampled clock or CPU
counter could decrease between samples while the window still reported
`measured`; a child-CPU counter decrease could also leave the
product-process-only result true. The evaluator now rejects nonfinite and
nonincreasing sample clocks, decreasing process or child CPU counters, and
nonfinite duration inputs. The reproduction failed before the repair, then
passed; all 16 focused resource/host-evaluation tests and both sampler and
six-window synthetic self-checks passed. This validates arithmetic rejection
paths, not ARM or Intel product resource budgets.

## Minimum owner-assisted follow-up

Before asking the owner to act, prepare the exact signed candidate and a bounded run plan: candidate/version, private output directory, permitted store/key namespace, steps, normal shutdown and forced-stop fallback. Obtain approval for the particular session/privacy/Keychain operations. Existing build permission does not cover them.

For a newly justified live round, rather than automatically repeating prior evidence, start with one 30–60 second current-candidate count → pause/resume → normal quit/restart trial using only agreed shortcuts. Record starting/ending aggregate totals and successful durable completion, without real text or event sequences. Then schedule separate exclusion/foreground and lock/sleep trials; do not compress permission changes, user switching and Keychain failures into one opaque run. Exclusion trials must record and restore the original switch state. Lock/sleep recovery uses explicit menu **Start** and fresh checks; do not promise automatic resume or a one-second loss limit.

Continuous boundary evidence needs a privacy-safe observation mechanism before the owner is asked to reproduce it. Coarse state transitions and numeric aggregate/durable counters may be retained; keystroke timestamps, text and raw sequences may not. Screenshots at the endpoints alone do not establish zero capture throughout a closed interval. Fast-user-switch, permission and test-Keychain trials require their own approved setup; Intel and public release remain independent work.

The current Debug privacy journal can also record `protectedGateEntries`, a cumulative count of operations admitted by `KeyAvailabilityGate` through its synchronous and asynchronous guarded entry points. A locked or stale attempt does not increment it. The value is absent when the recorder is not wired to the gate or the count overflows. This is a conservative diagnostic for paths using that gate; it does not establish that every protected read uses it or that a closed interval stayed closed between journal samples. No live lock or Keychain qualification is claimed from this offline instrumentation.
The closed-interval evaluator now treats a missing gate count as inconclusive, a decrease as invalid, and an increase between the close and reauthorization boundaries as an observed gate admission during closure. Earlier journals without this field remain usable for other observations but cannot satisfy this check.

An offline race test exposed a separate store lifecycle fault: `ObjectStore.bootstrap()` could suspend on key inventory, receive `closeProtectedSession()`, then resume and set the store phase to `freshInstall`. Git revisions, file versions, types and ordinary sequential tests cannot order an asynchronous continuation against a same-process close; the reproducer exercised that ordering directly. The store now invalidates the suspended bootstrap's session token on close and checks it after asynchronous key and journal work before publishing an opened phase or reconciling owned files. Product startup, load and save also run their asynchronous store steps under the current key-gate generation. The reproduction failed before the repair and passed afterward; a second test covers closure while the manifest key is pending. All 165 Store tests and 51 hostless product recovery tests passed, including save after a deliberate session close. These results establish the offline race repair, not real macOS lock or Keychain accessibility behavior.

A follow-up reproduction found the same ordering fault during first-installation manifest creation: a pending key request returned after session close and still committed `manifest.krenc`. Initial creation and the raw store read/write/delete paths now check the same session token after key retrieval, before plaintext return or file mutation; a late key result cannot repopulate the transient cache. The initial-creation reproduction failed before the repair and passed afterward. The five session-closure tests, all 168 Store tests, 51 hostless product recovery tests, and unsigned Debug App build passed for this follow-up candidate. These are offline results; no real Keychain or lock session was exercised.

A further failing-first reproduction paused cycle reset during Keychain version
inventory, closed the protected store session, reopened it, then released the old
inventory call. Before repair, that old reset completed and changed the current
cycle in the new session. Cycle reset and pending-journal continuation now retain
the original protected-session token across their asynchronous steps and check it
before further writes. Both closed-session regressions and all 170 Store tests
passed; the unsigned arm64 Debug App built and 53 hostless product recovery tests
passed. The first product XCTest attempt used incompatible DerivedData and failed
before running tests; the fresh test build produced the 53-test passing result.
This is an offline race repair, not a real lock or Keychain qualification.

Candidate review found a further asynchronous rotation boundary. A pending
Keychain read could return after the protected store session closed and let the
old migration create a ciphertext locator or replace the manifest. Two
deterministic regressions failed before repair and passed afterward.
Protected-reference sessions now retain the store session token across migration,
manifest reencryption, recovery and scans. Rotation checks the token and the
existing key gate after awaited key reads and before further file writes. A
separate test rejects a reference session reused after close and reopen. The
Store suite passed 172 tests before that last test was added; the last test
passed separately, and the SwiftPM Release build succeeded. These are offline
results, not a real lock or Keychain qualification.

For source commit `4a264da3b`, `PrivacyEgressTests` and `PrivacyBinaryAuditTests` passed 6/6, including the network-linked negative fixture. A fresh unsigned Release App built with arm64 and x86_64 slices; its only executable passed `Scripts/audit-product-network.sh`: SHA-256 `84e37ba693dff4ce3b4bd6c9b9f6759445440e83a22263aaedc5340ebbc0666d`, 1,854 undefined-symbol lines, 20,192 string lines, zero matches, `liveReceipt=false`. `codesign` reports an ad hoc linker signature without a Team ID. This is static evidence for that exact local executable. The final signed Release artifact remains unaudited.

For source commit `888438edddad74d5779d28a6b40be203174391a6`, `PrivacyEgressTests` and `PrivacyBinaryAuditTests` passed 6/6. An unsigned Release App build with `ARCHS="arm64 x86_64"` and `ONLY_ACTIVE_ARCH=NO` succeeded; `lipo -archs` confirmed both slices in the executable. `Scripts/audit-product-network.sh` passed on that exact executable: SHA-256 `8aa1be8f9a0cacc9e8f8890287f2133f40e65d76e9ca36f3868d8f424113fcf1`, 1,854 undefined-symbol lines, 20,132 string lines, zero matches, `liveReceipt=false`. This is static evidence for the specified unsigned candidate only. The final signed Release artifact has not been built or audited, and no live network observation is claimed.

For source commit `69e34284ea6af1f69f25e45a6f81933d68af5c66`, the same six privacy source and negative-fixture tests passed. Its unsigned universal Release App built successfully with arm64 and x86_64 slices. The exact executable passed `Scripts/audit-product-network.sh`: SHA-256 `89d44bbffd29c12707fba8f5bd35a88f962ca198e314793af9550615cd28d72b`, 1,854 undefined-symbol lines, 20,127 string lines, zero matches, `liveReceipt=false`. This was the next unsigned candidate; the signed Release artifact remained unaudited.

For earlier PR source commit `2095183e5dca3105f396984908a4da9e5fd9d7fb`, all six `PrivacyEgressTests` and `PrivacyBinaryAuditTests` passed, including the linked-socket negative fixture. A fresh Release App built with arm64 and x86_64 slices and no Developer ID signature; `codesign` reports only an ad-hoc linker signature with no Team ID. Its sole bundled executable passed `Scripts/audit-product-network.sh`: SHA-256 `2a8678a681f139bdfa7c27590ab0974eab00169088a8b76939a2d86ef2e4a48c`, 1,854 undefined-symbol lines, 20,127 string lines, zero matches, `liveReceipt=false`. This is static evidence for that exact local executable. The final Developer ID signed Release artifact has not been built or audited.

For product source commit `648144555b0bee70b819148f381de1d6aacbb54c` (the following `14c1eb1d` commit changed documentation only), all six `PrivacyEgressTests` and `PrivacyBinaryAuditTests` passed, including the linked-socket negative fixture. A fresh unsigned Release App built with arm64 and x86_64 slices. `codesign` reports only an ad-hoc linker signature with no Team ID, and the App contains one bundled executable with no Debug dylib. That exact executable passed `Scripts/audit-product-network.sh`: SHA-256 `3df2deb909f04a576c8270ad8abe95171f2d9cbffa4a44dc1b732fd22b383a08`, 1,854 undefined-symbol lines, 20,176 string lines, zero matches, `liveReceipt=false`. This is static evidence for the local unsigned executable; the final signed Release artifact has not been built or audited. No live network observation was performed.
