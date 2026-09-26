# Post-merge verification — 2026-09-26

This is an offline follow-up on merge `ec5583d73a1fc936bea1786708ba0717d8b47fbd`.
It is not Phase 1 acceptance, not a signed Release qualification, and not a live trial.

The product tree matches that merge. The only uncommitted change is
`App/KeyRecordAppTests/ProductRecoveryQuitTests.swift`. `docs/PROJECT_STATUS.md` in the
main checkout was left as the other agent wrote it and was not committed.

## Automatic save

Existing recovery tests call `flushWhileUnlocked` or `waitDurable`. They do not show
that the collecting pulse itself writes. Two permanent tests now do.

`testBackgroundPulsePersistsCountsWithoutAnExplicitFlush` starts the production
composition with synthetic input, a temporary encrypted store, and stand-in host
boundaries. It presses 2, then 1, and reads the store with `AggregatePersistence.restore`.
That read does not stage, tick, or flush. The test does not call `flush`, `waitDurable`,
`finishIssuedWrites`, or Quit. Each read has an 8 second bound and fails with the last
disk total, pending flag, unflushed flag, pulse count, and last read error.

Result on this machine: passed in 2.118 seconds. Disk total went 2, then 3.

`testDiskReadDoesNotSaveWhenThePulseIsStopped` stops the pulse through the existing
fixture hook, presses 2, and reads for the same 8 second bound. Passed in 8.043 seconds.
Disk stayed 0 while the in-memory count was still unflushed, so the read path is not
what saved the first test.

Negative control, not left in the tree: `makePulse()` was temporarily changed to an
empty task and the first test was run again. It failed in 16.540 seconds:
`disk=0 expected=2` and then `expected=3`, `pending=false`, `unflushed=true`,
`pulse=1`, `lastError=none`. `ProductComposition.swift` was restored.
`git diff` is only the test file.

Because that file holds the recovery suite, the whole suite was run after the restore:
42 tests, 0 failures, 52.919 seconds. Log:
`.build/postmerge-recovery-suite.log`.
The empty-pulse failure log is `.build/postmerge-negative-control.log`.

No product defect was established. The empty pulse left counts unflushed, which is
what the test is for.

## Signed Debug candidate

Not launched. Not copied over the daily app. The real store
`~/Library/Application Support/com.keyrecord.app/store` was not opened; its directory
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

When a later round is approved, isolation is:

- `KEYRECORD_TRIAL_STORE` = this worktree `.build/postmerge-live/<round>/store`
- `KEYRECORD_TRIAL_NAMESPACE` = `com.keyrecord.trial.postmerge-<round>`
- `KEYRECORD_PRIVACY_INTERVAL_PATH` = `.build/postmerge-live/<round>/intervals.jsonl`
- `KEYRECORD_DIAGNOSTIC_SUMMARY_PATH` = `.build/postmerge-live/<round>/summary.json`
- `KEYRECORD_SYSTEM_WITNESS_SECONDS` = at most 300, and only together with the journal
- `KEYRECORD_LOCAL_CAPTURE=1` only for that approved launch

Rejected or partial trial settings must not fall back to `com.keyrecord.app` or the
real store. No live launch has used these paths yet.

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

Candidate: the same signed Debug bundle. Second trial process 84957, store
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

Candidate: the signed Debug bundle rebuilt after the secure-input interval fix.
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

## Resource measurement

Not run. Functional host checks have not passed on this merge.

After they pass, and only with a separate approval, sample the already-running trial
process with `Scripts/measure-process-resources.sh`. Record process user+system CPU
against `CLOCK_MONOTONIC`, `ri_phys_footprint` mean and sampled peak, raw samples,
valid duration, and sampler overhead. Do not use RSS. Do not treat sleep, lock
interruption, or a missing sample as a pass. A short window is exploratory. One ARM
machine is not Intel and is not formal FR-S2. Collecting and paused are separate
windows. The collecting window includes the 250 ms Secure Input poll.
