# Post-merge verification — 2026-09-26

This report contains historical offline preparation and later owner-approved host
observations after merge `ec5583d73a1fc936bea1786708ba0717d8b47fbd`. It is not Phase 1
acceptance or signed Release qualification. Product/test changes were subsequently
committed as `d89d53376e89c7fbef76fc4d8576327ddcf2a8a3`; documentation was extended at
`4c5d16656146e46abfbdf7e0517419289571036c`. That candidate is not product-identical to
the merge: it changes Secure Input visibility/recovery and diagnostic intervals.

The offline preparation and rounds A/B2 below used the merge-derived product. B3,
C and the resource windows used the rebuilt precommit tree later committed as
`d89d5337`. Retained logs do not embed Git identity, so this attribution rests on
the owner report and build chronology, not an independent exact-commit rebuild.
The subsequent independent review and repairs are recorded at the end. Historical
live observations must not be presented as fresh host tests of those later repairs.
The main checkout's separate project-status update was preserved during the original
agent's work; it was not part of the original two commits.

## Initial offline checkpoint: automatic save

Existing recovery tests call `flushWhileUnlocked` or `waitDurable`. They do not show
that the collecting pulse itself writes. Two permanent tests now do.

`testBackgroundPulsePersistsCountsWithoutAnExplicitFlush` starts the production
composition with synthetic input, a temporary encrypted store, and stand-in host
boundaries. It presses 2, then 1, and reads the store with `AggregatePersistence.restore`.
That read does not stage, tick, or flush. The test does not call `flush`, `waitDurable`,
`finishIssuedWrites`, or Quit. Each read has an 8 second bound and fails with the last
disk total, pending flag, unflushed flag, pulse count, and last read error.

The retained initial suite log records a pass in 2.101 seconds. Disk total went 2, then 3.

`testDiskReadDoesNotSaveWhenThePulseIsStopped` stops the pulse through the existing
fixture hook, presses 2, and reads for the same 8 second bound. The retained initial suite records a pass in 8.092 seconds.
Disk stayed 0 while the in-memory count was still unflushed, so the read path is not
what saved the first test.

Negative control, not left in the tree: `makePulse()` was temporarily changed to an
empty task and the first test was run again. It failed in 16.540 seconds:
`disk=0 expected=2` and then `expected=3`, `pending=false`, `unflushed=true`,
`pulse=1`, `lastError=none`. `ProductComposition.swift` was restored.
At this initial checkpoint, `git diff` contained only the test file.

Because that file holds the recovery suite, the whole suite was run after the restore:
42 tests, 0 failures, 52.919 seconds. Log:
`.build/postmerge-recovery-suite.log`.
The empty-pulse failure log is `.build/postmerge-negative-control.log`.

No product defect was established by this initial automatic-save check. The empty
pulse left counts unflushed, which is what the test is for.

## Initial offline checkpoint: signed Debug candidate

At this preparation checkpoint, not yet launched. Not copied over the daily app. The real store
`~/Library/Application Support/com.keyrecord.app/store` was reported not opened; its directory
modification time was still 2026-09-24 15:33:47.

| Item | Value |
| --- | --- |
| Source | `ec5583d73a1fc936bea1786708ba0717d8b47fbd` |
| Uncommitted product change | none |
| Configuration | Debug, `ONLY_ACTIVE_ARCH=YES`, arm64 only |
| Signing | project Debug settings: Automatic, team `P3W62C39TN`, identity Apple Development |
| Bundle | `.build/postmerge-signed-debug/Build/Products/Debug/KeyRecordApp.app` |
| Check | `codesign --verify --strict` passed; designated requirement satisfied |

An earlier attempt set `DEVELOPMENT_TEAM` to the parenthetical id in the certificate
name. Xcode then looked for a Mac Development certificate for that id and failed.
The certificate's team is `P3W62C39TN`, which is already the project setting.
The successful build used that setting and did not edit the project.

`xcodebuild` registered the bundle with Launch Services. That registration was removed
with `lsregister -u` on this bundle path only. The app was not started.

The subsequent approved rounds used the following isolation configuration:

- `KEYRECORD_TRIAL_STORE` = this worktree `.build/postmerge-live/<round>/store`
- `KEYRECORD_TRIAL_NAMESPACE` = `com.keyrecord.trial.postmerge-<round>`
- `KEYRECORD_PRIVACY_INTERVAL_PATH` = `.build/postmerge-live/<round>/intervals.jsonl`
- `KEYRECORD_DIAGNOSTIC_SUMMARY_PATH` = `.build/postmerge-live/<round>/summary.json`
- `KEYRECORD_SYSTEM_WITNESS_SECONDS` = at most 300, and only together with the journal
- `KEYRECORD_LOCAL_CAPTURE=1` only for that approved launch

Rejected or partial trial settings must not fall back to `com.keyrecord.app` or the
real store. No live launch had used these paths at the initial offline checkpoint. Unchanged
directory modification time is not proof that a directory was never read.

## Round A live check — 2026-09-26 19:39–19:43

Candidate: the signed Debug bundle above. Process 79140. It exited before this note.
Evidence: `.build/postmerge-live/round-a/intervals.jsonl` (398 records) and
`summary.json`. The real store directory time was still 2026-09-24 15:33:47 after exit.
This is one host observation, not Phase 1 acceptance.

Menu Quit ran while collecting. The quit record says `invocation=menu`,
`quitDecision=terminate`, `lifecycleFlushOutcome=saved`, and both the reducer and
scheduler reported nothing unsaved. `sessionLiveAfter` was false and the phase was
`stopped`. The summary file still has `captureSessionLive=true`; that flag was copied
before the quit record's own live-session read. Issued, returned, succeeded and durable
flushes are all 29. Failures, timeouts and invalidations are 0.

Counter split:

| Interval | Aggregate | Durable flushes | What the records show |
| --- | --- | --- | --- |
| Before the lock closed the session (seq 205) | 6 | 20 | Already durable. Counts stepped 1…6 while the witness still read unlocked. |
| Closed interval seq 205–357, 75 observe lines | stayed 6 | stayed 20 | Phase `blocked`, session not live, statistics hidden, `blockedReason=sessionLocked`. Handoff, normalization, publication and protected reads did not increase. |
| After explicit Start (seq 359) until menu Quit | 6 → 10 | 20 → 29 | Start's own record: phase `blocked` → `collecting`, fresh readiness `lock=unlocked, secure=disabled`, session live. |

The two screenshots match those totals: shortcut rows 4+1+1=6, then 6+2+2=10.
TextEdit is 5 then 8. KeyRecord itself is 1 then 2. The aggregate did not stay at 5
and then add 3, because two key events were attributed to KeyRecord and the TextEdit
events are split across modifier-side groups. The steps are 1 through 10 with no
repeated value, so the later four are new counts, not a replay of the first six.

Unlock did not leave the closed interval. A witness line read `unlocked` while the
phase was still `blocked` and the aggregate was still 6. The interval ended only when
Start began a new session (`captureSessionStarting`). The earlier "Start stays blocked"
observation did not happen on this run. No cause is assigned to that older run.

A witness line during the lock also read Secure Input `enabled`, then `disabled`
before unlock. That is the lock-screen reading in this round. It is not the separate
Secure Input round.

First-run window: Start from `unstarted` returned `not-blocked-or-failed` and requested
consent instead of collecting. The first Accept record then shows `phaseAfter=collecting`
and a live session, before any counted key. Later Accept records have `phaseBefore=collecting`.
The window keeps a Consent tab after that, and the first saved preferences use the
English locale default while the pre-consent text follows the system language.

## Round B live check — 2026-09-26

Candidate: the original merge-derived signed Debug bundle, before the later fix. Second trial process 84957, store
`.build/postmerge-live/round-b2/`. Evidence: `intervals.jsonl` and `summary.json`
in that directory. The real store directory time was still 2026-09-24 15:33:47.
This is not Phase 1 acceptance.

Menu Quit: `invocation=menu`, `quitDecision=terminate`, `lifecycleFlushOutcome=saved`,
nothing unsaved in the reducer or scheduler. Issued and durable flushes are both 14.
Final aggregate is 6. Published shortcut total is 6. Bare-key total is 0. Key-down
callbacks are 6.

The useful secure-input window is witness seq 443–489, 47 lines. Every line reads
`secureInputReadStatus=enabled`, phase `collecting`, capture session not live.
Aggregate stays 3. Handoff stays 12. Normalization stays 6. Durable flushes stay 9.
Protected reads and publication do not increase. Those 3 counts were recorded earlier,
while the read was `disabled` and the session was live (seq 405–407).

No Start action occurs after that window. The quit line already shows aggregate 6
and a live collecting session. The extra 3 are present in the final total and are
not a replay of the first 3.

The diary does not contain a `disabled` read after seq 489, and it does not contain
a closed interval for this hold. The 300-second witness ended while the field was
still enabled. Statistics visibility stayed true throughout those 47 lines. The
earlier attempt in `round-b` is not this result: its hold was not written, and its
displayed 8 was the shortcut total beside 341 bare keys.

## Round B replay — 2026-09-26 21:05

Candidate: the signed Debug bundle rebuilt after the Secure Input interval and
visibility fix, from the precommit tree later committed as `d89d5337`. Before this
rebuild, the selected `ProductRecoveryQuitTests` suite passed 42/42 in 53.713 seconds
(20:54:31–20:55:25, `.build/postmerge-secure-interval-suite.log`). The signed Debug
build completed at 20:55:50 (`.build/postmerge-signed-debug-build.log`). Neither
result is a complete App suite, package suite, or Release build.
Trial process 99097, store `.build/postmerge-live/round-b3/`. The password field
was not shown until the journal already had a live collecting session, secure
input `disabled`, and aggregate 4. The real store directory time stayed
2026-09-26's earlier reading of 2026-09-24 15:33:47. This is not Phase 1 acceptance.

Closed interval seq 140–377, cause `secureInputMonitor`, phase stayed `collecting`.
It has a begin, 116 observe lines, and an end. While the fresh read was `enabled`
(seq 142–374), the session was not live and statistics were hidden. Aggregate stayed
4, handoff stayed 14, normalization stayed 8, and protected reads did not increase.
Durable flushes moved 8 → 9: one write of counts already collected, not a new input.
No Start action occurred after the interval opened.

The end line is live and visible again, aggregate still 4. The next witness reads
`disabled`. Counts then stepped 5, 6, 7. Menu Quit terminated with a saved flush.
Issued and durable flushes are both 15. Published shortcut total is 7. Key-down
callbacks are 7. The extra count before the hold (4 rather than 3) remained inside
the frozen total and was not replayed.

## Round C blocked Quit — 2026-09-26 21:14

Candidate: the same rebuilt signed Debug bundle. Trial process 1679, store
`.build/postmerge-live/round-c/`. No password field was opened. The real store
directory time stayed 2026-09-24 15:33:47. This is not Phase 1 acceptance.

Collecting reached aggregate 3 and 5 durable flushes before the lock. The closed
interval begins at seq 78 with `protectedStateClosed`, phase `blocked`,
`blockedReason=sessionLocked`. It has 43 observe lines. Aggregate stayed 3, handoff
stayed 12, normalization stayed 6, and durable flushes stayed 5. The fresh lock read
went `locked`, then `unlocked`, while the phase stayed blocked and the session stayed
not live. There is no end line: Quit happened while that interval was still open.

Menu Quit begins at seq 166; its result at seq 167 has `invocation=menu`, `phaseBefore=blocked`,
`quitDecision=terminate`. Nothing was unsaved before or after, and the lifecycle flush
was `notInvoked`. `phaseAfter` stayed `blocked` because the blocked reducer does not
handle quit. The process still exited: it is gone, and `summary.json` was written.
Issued and durable flushes are both 5. Failures, timeouts and invalidations are 0.
Published shortcut total is 3. Key-down callbacks are 3. This was not a cancelled quit
and not a forced kill.

## Resource measurement — 2026-09-26 21:46 and 22:17

Same signed Debug bundle, trial process 3594, store
`.build/postmerge-live/round-resource-paused/`. Diagnostics were enabled and are
included in the numbers. Footprint is `ri_phys_footprint`, not RSS. Warmup samples
are excluded from CPU and footprint. Neither window slept, locked, or lost samples.
The owner reported aggregate stayed 0 within each window. Child CPU was 0. These are one ARM machine, candidate-length
windows, `qualification=not-a-product-pass`. They are not formal FR-S2 and do not
stand in for Intel.

| Window | Effective seconds | Retained samples | Footprint samples | CPU, one logical core | Footprint mean | Sampled peak |
| --- | --- | --- | --- | --- | --- | --- |
| Paused | 599.808 | 659 | 598 | 0.0384% | 32791194 bytes | 32801824 bytes |
| Collecting, idle while armed | 599.805 | 659 | 598 | 0.0482% | 33011473 bytes | 33063968 bytes |

The collecting window is idle while armed, not a typing workload. The owner reported
zero aggregate growth during each measurement window; the resource samples do not
contain aggregate counters. The whole trial continued beyond those windows and its
final summary has 61 counts, which must not be attributed to the measured windows.
The 250 ms Secure Input poll runs in the collecting window. The
difference is not a subtracted poll-cost claim. Raw archives:
`paused-candidate.json` and `collecting-candidate.json` in the trial directory.
Sampled peak is not a bound on values between samples.

## Independent follow-up repair — 2026-09-26

Review of `4c5d1665` found four defects beyond the earlier bounded host scenarios:

- Unsigned Release failed to compile because production monitoring referenced a
  Debug-only `secureInputSawLiveSession` property.
- The first collecting poll could read `unknown` and leave the already-started
  capture session live, until a disabled poll had initialized that latch.
- An old enabled poll could finish after the coordinator had recovered against
  fresh disabled reads, then hide statistics indefinitely despite a live session.
- The diagnostic closed interval could stay open after a validated new capture
  session had begun accepting events, misclassifying resumed input as closed input.

Two controlled production-composition tests and one Core recorder test failed
before repair. The repair removes the latch, closes privacy before asynchronous
recovery, reconciles disabled state even when capture is already live, and guards
post-await changes with the existing monitor generation. It ends diagnostic
intervals at `captureSessionStarting`, before event admission, rather than requiring
an end line already reporting a live session. The steady disabled/live poll does
not resynchronize or recreate a deliberately stopped pulse.

Initial repair verification retained a failed stopped-pulse control; narrowing that
steady-state branch and guarding the final liveness read fixes it. An initial
package run also failed the existing path-safety test in the `/tmp` worktree alias;
the same review checkout was moved to a non-symlink path, without weakening the
validator. Those failures remain in local review evidence rather than being erased.

No new real-host launch, keyboard capture, lock, password field or resource trial
was performed for this follow-up. Earlier live/resource observations above remain
historical and do not establish this repaired candidate's host or performance
qualification. Review evidence is retained locally under
`.omo/evidence/postmerge-review-4c5d1665/` in the main checkout; these files are not
promised in a fresh clone.

Final repair validation for product commit `5072a1e2` (subsequent documentation-only
commit does not change these sources):

| Check | Result |
| --- | --- |
| Fresh unsigned Debug arm64 test build | Passed |
| Entire ProductRecoveryQuitTests selection | 44/44, 53.828 seconds |
| SwiftPM package tests | 518/518, zero failures |
| Fresh unsigned universal Release | Passed, arm64 + x86_64 |
| Release project/bundle boundary audit | Passed; no forbidden diagnostic tokens |
| Static product network audit | Passed; not a live traffic observation |

The full App XCTest suite and independent final-commit review are separate checks,
not inferred from the selected 44 tests. No signed Release runtime, Intel execution
or new performance claim follows from successful compilation. The previous failed
Release build and the failing-first tests are retained beside the final logs.
