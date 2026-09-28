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
| FR-P1 data stays on device | Product source scan and binary audit tooling have positive and negative fixture coverage; this milestone has no network client ([privacy checks](PRIVACY_BOUNDARIES.md)) | Run the source tests and audit the exact Release executable being qualified; bind results to that candidate. Prior packet observations remain invalid historical records | Use existing `PrivacyEgressTests` and `audit-product-network.sh`; review any future update checker separately | No packet-capture round is required |
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
The hosted controller now checks its authority preflight for every lock
transition and requests a fresh unlocked witness for the delete/missing read;
loss of that witness blocks the step before another Keychain operation. This is
offline controller behavior, not a qualified system lock observation.
The scenario report also rejects a claimed CRUD, delete/missing read, or cleanup
PASS when its recorded Keychain call count does not match the operations that
step must have executed; a zero-call fake cannot qualify those steps.
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
3. On **each** native ARM and Intel reference host, run 60 seconds warmup, 600 seconds typing and 600 seconds idle measurement, repeated three times; schedule while the owner is available. Never prevent sleep; if sleep or session loss interrupts a window, retain it as interrupted and rerun later with approval.
4. CPU = process CPU seconds / elapsed monotonic seconds × 100, relative to one logical core. Formal windows require an observed sample at or after the full 600-second endpoint; a near-endpoint sample below 600 seconds remains interrupted. Report typing and idle medians separately. Typing <1%, idle <0.1%. Record physical footprint across both measured phases at a stated cadence, their means and peaks; each phase must stay below 100 MB. Sampled peak is not proof no inter-sample transient occurred. Do not substitute RSS, whole-machine CPU or a ten-minute wall clock dominated by sleep.
5. Keep raw samples, measured duration and work completed. Report controller/fixture overhead explicitly; do not subtract an arbitrary baseline or turn an XCTest failure into a product regression claim. Empty/missing/interrupted evidence is not PASS. Compare input and durable aggregate totals to ensure the workload really ran.

The private native ARM Debug trial package prepared from this PR has bundle ID
`com.keyrecord.trial.performance5c54a178`, a distinct display name and the
required isolation marker. Its ad-hoc signature passed strict verification.
The loader digest is `9e4aa08ea71d55e2cc6e651ff59ec40152e9df848f141cf6d80aaaaf41d69480`;
the actual Debug code digest is `86babf978c04e9955cd1e5f9e3dfaf90f4756ead20dd178f3a3d354a7b88f559`.
The controller's `--check` accepted those exact files without launching the
App. The sampler and six-window evaluator passed synthetic self-checks only;
there are no product resource samples or Keychain effects from this preparation.

## Minimum owner-assisted follow-up

Before asking the owner to act, prepare the exact signed candidate and a bounded run plan: candidate/version, private output directory, permitted store/key namespace, steps, normal shutdown and forced-stop fallback. Obtain approval for the particular session/privacy/Keychain operations. Existing build permission does not cover them.

For a newly justified live round, rather than automatically repeating prior evidence, start with one 30–60 second current-candidate count → pause/resume → normal quit/restart trial using only agreed shortcuts. Record starting/ending aggregate totals and successful durable completion, without real text or event sequences. Then schedule separate exclusion/foreground and lock/sleep trials; do not compress permission changes, user switching and Keychain failures into one opaque run. Exclusion trials must record and restore the original switch state. Lock/sleep recovery uses explicit menu **Start** and fresh checks; do not promise automatic resume or a one-second loss limit.

Continuous boundary evidence needs a privacy-safe observation mechanism before the owner is asked to reproduce it. Coarse state transitions and numeric aggregate/durable counters may be retained; keystroke timestamps, text and raw sequences may not. Screenshots at the endpoints alone do not establish zero capture throughout a closed interval. Fast-user-switch, permission and test-Keychain trials require their own approved setup; Intel and public release remain independent work.
