# Short formal performance round

> Status reconciliation (2026-10-01): this is a dated record for the candidates and rounds named below. “Current”, “next”, “pending” and BLOCKED refer to that checkpoint, not today's work queue. The approved Apple Silicon Phase 1 MVP is complete and merged; see [current acceptance](PHASE1_ACCEPTANCE.md) and [roadmap](ROADMAP.md). Original observations and failures retain their scope; these instructions do not authorize another host round.

Source `a604ad535` implements the owner-requested formal protocol: typing and
idle once each, 30 seconds warmup plus 120 seconds measurement per window, with
a two-second drain tail. The approved replacement typing and idle windows both
completed with the repaired `1cf51a056` controller; host evaluation is within-budget.

## Completed replacement session

The owner approved continuation and confirmed Collecting separately for both
windows. The signed product remains `a604ad535`, on Apple M3 / Mac15,12 with
16 GiB RAM, native arm64, macOS 27.0 build 26A428. Each window used an independent
process and fresh isolated store/Keychain namespace. Diagnostics were enabled
and included in target overhead.

| Measurement | Typing | Idle | Budget |
| --- | ---: | ---: | --- |
| CPU, percent of one logical core | 0.0983331% | 0.0807117% | <1% / <0.1% |
| Mean physical footprint | 33.9289 MB | 32.8800 MB | <100 MB |
| Sampled peak physical footprint | 34.0634 MB | 33.0476 MB | <100 MB |
| Effective measurement after warmup | 120.0719 s | 120.4332 s | >=120 s |
| Replay duration / ticks | 152.0098 s / 1,520 | 152.0049 s / 1,520 | 1,520 |
| Accepted events / durable key downs | 5,100 / 2,550 | 0 / 0 | Matches workload |

Both controller invocations exited 0 with outcome measured, no invalidReasons,
completed replay and normalExit=true. Typing's 145 issued writes all succeeded
durably; idle issued no writes. Both summaries report no write/read failure,
timeout, overflow or journal failure. After both runs, an unsandboxed exact-name
process check found no KeyRecordApp process. Cached captureSessionLive in the
pre-quit aggregate summary is not the exit witness.

The controller's `--evaluate --session` command exited 0 and wrote
`/private/tmp/keyrecord-performance-20260929-a604ad535-retry1/host-report.json`:
outcome within-budget, windowCount 2, productPass false. Both raw sample archives
were recomputed by that evaluator. Window subdirectories retain their replay,
aggregate summary, resource archive and controller report. Logs are
`/private/tmp/keyrecord-performance-controller-diagnosis/typing-retry1-controller.log`
and `idle-retry1-controller.log` in the same directory.

This completes the agreed short native Apple Silicon performance measurement
for this signed Debug fixed-replay candidate. It does not qualify the full MVP,
Release, event-tap overhead, other hardware/OS versions or long-term endurance.
The original invalid typing window below is preserved separately. No further
owner action or repeat is required for this performance session.

## First typing window and controller repair

After the owner enabled Input Monitoring and confirmed Collecting, the signed
`a604ad535` product completed 1,520 ticks in 152.006 seconds, accepted 5,100
replay events and saved 2,550 key downs. All 145 issued writes succeeded durably;
no write/read failure was recorded. Normal Quit succeeded and no product process
remained. The retained resource window reports measured: CPU 0.0873278% of one
logical core, mean physical footprint 33.8712 MB and sampled peak 33.8996 MB.
These are observations, not accepted performance results: the controller's
original `trial-report.json` says invalid and remains unchanged.

Artifacts: `/private/tmp/keyrecord-performance-20260929-a604ad535/typing-1/`
contains `resource-typing.json`, `performance-replay.json`, `summary.json` and
`trial-report.json`. The sibling idle directory has not been used.

The controller first queried `NSRunningApplication.executableArchitecture`
after normal Quit. A synthetic AppKit fixture reproduced a return of -1 when
first queried after exit, versus arm64 (16777228) when queried while running.
The latter value remained cached after exit. Full Swift recomputation of the
retained resource result equals the stored result, ruling out JSON rounding or
an extra result-field mismatch in this archive. The old report did not persist
every validation predicate, including the sampler exit code, so the invalid
record is not retroactively promoted.

The controller now snapshots architecture while the process is alive and keeps
the same native-architecture requirement. It also emits `invalidReasons` for
each failing existing check. Product code, signing and installed App are unchanged.
Controller build and two-window synthetic evaluation self-check passed.
Diagnostic fixture sources and comparison tool are retained at
`/private/tmp/keyrecord-performance-controller-diagnosis/`.
The owner subsequently approved and readied the replacement session above.

Replacement session was prepared at
`/private/tmp/keyrecord-performance-20260929-a604ad535-retry1`, with fresh 0700
`typing-1` and `idle-1` children and namespaces ending in `.typing2` and `.idle2`.
Both repaired-controller `--check` calls returned ready, launched=false against
the unchanged signed product. The checks created no runtime store or Keychain
item; the subsequently authorized runs used these isolated namespaces.

## Approved provisioning result

The owner authorized one Xcode account/profile attempt. It completed in 33.3
seconds, exit 0, with BUILD SUCCEEDED and no detected account/payment/build
error. No second attempt ran. Log:
`/private/tmp/keyrecord-performance-a604ad535/approved-provisioning-build.log`.
The watchdog started a dedicated process group, capped the operation at 120
seconds and would stop on errors or recognized account/payment prompts.

The signed App is at
`/private/tmp/keyrecord-performance-a604ad535/build/Build/Products/Debug/KeyRecordApp.app`
and is installed separately as
`~/Applications/KeyRecord Performance Trial 20260929.app`.
Strict deep signature verification passed. The performance controller checked
both fresh window roots against the signed artifact, then checked the installed
package, reporting ready and launched=false. No KeyRecordApp process remained.
The MVP Trial was not replaced. At that preparation checkpoint, these checks
established signing/profile readiness only; the later runtime result is above.

The owner subsequently enabled Input Monitoring for the exact new Performance
Trial and confirmed readiness. The original prepared runs used namespaces
`com.keyrecord.trial.performance.mvp20260929.typing1` and
`com.keyrecord.trial.performance.mvp20260929.idle1`, respectively, with the fresh
window directories below. Each run requires Start/consent; do not open
the App manually without its isolation controller. Any unexpected prompt during
measurement requires a stop and a separately prepared continuation.

## Prepared artifacts

- Dedicated bundle: `com.keyrecord.trial.performance.mvp20260929`.
- Display name: `KeyRecord Performance Trial`; required-isolation marker true.
- Team for local development signing: `P3W62C39TN`.
- Unsigned arm64 App build succeeded at
  `/private/tmp/keyrecord-performance-a604ad535/unsigned-build/Build/Products/Debug/KeyRecordApp.app`.
  Both loader and Debug product dylib are arm64. This artifact is not runnable
  qualification evidence and will not be used for permission or Keychain trials.
- Current controller and sampler builds passed; binaries are under the isolated
  worktree's `.build/out/Products/Debug` directory.
- Initially fresh, owner-only 0700 session directory:
  `/private/tmp/keyrecord-performance-20260929-a604ad535`, with `typing-1` and
  `idle-1` children. Typing now contains the retained runtime artifacts above;
  idle is still empty. Preparation itself created no store or Keychain item.
- The existing installed MVP Trial and all sleep-round data are unchanged.

## Initial signing blocker (resolved above)

A signed build using existing local assets, with no provisioning updates,
failed with Xcode exit 65: no Mac App Development profile exists for
`com.keyrecord.trial.performance.mvp20260929`. Log:
`/private/tmp/keyrecord-performance-a604ad535/local-signing-build.log`.
The only local profile inspected authorizes
`P3W62C39TN.com.keyrecord.trial.mvp20260929`, not the performance bundle.
An unchanged dedicated-performance identity check prevents substituting the
MVP App or weakening profile checks to launch an unusable package.

The requested account operation needed owner authorization: one Xcode attempt, at
most 120 seconds, using the existing developer account to register the dedicated
trial identifier if needed and obtain/create its matching development profile,
then build. Stop on account login, payment/subscription prompts or signing
errors. Do not launch a product, change TCC or create trial statistics as part
of that operation. The earlier one-time account authorization covered the MVP
identifier only and is not reused here. This is local Debug provisioning, not
distribution signing or notarization.

The owner approved that request once, with the result above. After signing, verify the package and both empty window directories
with `KeyRecordPerformanceTrial --check`. Only then prepare installation and
the separately approved/readied live sequence: first typing, then idle, each
starting with owner Start/consent and ending with normal Quit and summary review.
Unexpected permissions, Keychain or restart prompts stop the round. Keep the
computer unlocked and do not prevent sleep. No physical typing is required.

## Evidence limits

The preceding 35 package tests, hostless product replay/store test and two tool
self-checks passed. The first native typing observation remains invalid;
replacement typing and idle now retain accepted-event/durable-total and
raw-sample evidence with a within-budget host evaluation.
Current controller/evaluator identity, full endpoint, sleep/session, budget and
normal-exit checks remain in force. Fixed replay omits actual system event-tap
cost; five-minute measurement is not a claim about long-term endurance.

At this checkpoint the push CI job for `a604ad535` passed in 4m30s; its PR CI job
was still pending. The unsigned build log is adjacent to the signing log as
`unsigned-build.log`; it does not establish signing or runtime Keychain access.
