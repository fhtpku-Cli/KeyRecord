# Explicit Command chord check

> Status reconciliation (2026-10-01): this is a dated record for the candidates and rounds named below. “Current”, “next”, “pending” and BLOCKED refer to that checkpoint, not today's work queue. The approved Apple Silicon Phase 1 MVP is complete and merged; see [current acceptance](PHASE1_ACCEPTANCE.md) and [roadmap](ROADMAP.md). Original observations and failures retain their scope; these instructions do not authorize another host round.

Status: completed after explicit owner approval and a separate readiness reply.
The bounded two-chord check matches expected counts and the owner confirmed
left Command twice and TextEdit twice in the expanded paused UI. Normal early
Quit completed; exact PID 27425 is gone. No automatic repeat is authorized.
The preceding [modifier round](CURRENT_MODIFIER_TRIAL_20260930.md) is preserved.
Its two bare-key counts match the owner's clarified standalone A procedure; it
does not establish a classification defect or complete Command+A acceptance.

## Completed result

The owner approved this round, then explicitly confirmed blank TextEdit was ready.
Before launch, whole-bundle comparison again matched source `426969c9f` staging,
and the installed controller `--check` passed. No installation or product source
change occurred. The retained foreground controller launched PID `27425` with
the root and namespace below. The owner chose Start/consent and replied started;
the journal confirmed Collecting, open actual queue and open key gate before the
explicit hold-Command/press-A instruction was sent.

The owner followed the instructed sequence, chose Pause, opened Aggregates and
expanded exact modifier details. The owner reported verbatim:
`left 两次 文本编辑两次`. This is owner-observed rendered side/count and application
evidence; no new screenshot or accessibility-tree inspection was performed.
Sequence 59 confirms Paused with the actual queue closed before that reply.

The assistant then created `modifier-quit.request`. The controller returned
`normalQuitRequested=true` and `exited=true quitRequested=true failed=false`, exit
code 0, before its automatic deadline. A read-only exact-PID check found no
remaining process. Quit action details show Paused to Stopped, no live session,
and no unsaved reduction or scheduler work.

| Final observation | Result |
| --- | --- |
| Key-down / key-up / flagsChanged callbacks | 2 / 2 / 6 |
| Accepted / closed / overflow handoffs | 10 / 0 / 0 |
| Aggregate delta | 2 |
| Last published shortcut / bare-key totals | 2 / 0 |
| Owner-reported expanded side / application counts | left Command 2 / TextEdit 2 |
| Issued / returned / successful / durable writes | 5 / 5 / 5 / 5 |
| Failed / timed-out / invalidated writes | 0 / 0 / 0 |
| Snapshot read failures / tap-disabled events | 0 / 0 |
| Final actual queue / live session | closed / false |

Preparation markers at sequences 35, 40 and 52 have accepted=0 and aggregate=0;
sequence 55 has accepted=10 and aggregate=2. The input falls between preparations
three and four without a recorded preparation at an intermediate count. These
remain non-atomic cumulative observations, not a physical-event trace. The initial
Command-only press/release adds no aggregate increment within this bounded result.

This completes the narrow current-candidate Command+A, left-side reconstruction,
TextEdit attribution, paused-row inspection and reported durable-save check.
It does not change the historical unknown-side or standalone-A results, and it
does not establish restart readback, native accessibility, exhaustive protected
reads, independent OS lock authority, complete hosted lifecycle or collecting
Release qualification. Preserve the occupied root and all three output files.

## Candidate and isolation

Reuse the installed `~/Applications/KeyRecord MVP Trial 20260929.app`, source
`426969c9f`, bundle ID `com.keyrecord.trial.mvp20260929`. No rebuild, installation
or provisioning update is needed. Whole-bundle `diff -qr` against its signed stage
passes, including the Debug implementation dylib. Performance Trial is untouched.

The new private root `/private/tmp/keyrecord-phase1-chords-live-20260930` is mode
0700 and empty at the no-launch check; it is now occupied and preserved. The used trial Keychain namespace is
`com.keyrecord.trial.mvp20260929.phase1chords20260930`; preparation performed no
Keychain data operation and does not independently prove namespace emptiness.
The approved run used only its isolated encrypted store and Keychain namespace.

Controller source: `/private/tmp/keyrecord-phase1-chords-controller-20260930.swift`.
Executable: the same path without `.swift`. It reuses the previous controller,
changing only the isolated root, namespace and printed stage label. Compilation
with `swiftc -parse-as-library` passes; SourceKit's default script-mode diagnostic
does not use that required compile mode. Installed `--check` returned
`ready=true launched=false normalQuitSeconds=175 stopSeconds=180`.

The retained foreground controller requests normal Quit at 175 seconds, and at
180 seconds stops only its identified trial instance. An earlier
`modifier-quit.request` requests normal Quit. It refuses an occupied root or a
running instance of the same bundle ID. Outputs are `modifier-summary.json` and
`modifier-privacy.jsonl`. Preserve both; no automatic relaunch or deadline extension.
Stop on permission, authentication, restart or Keychain prompts without changing
permissions. No sleep, lock, performance repeat, packet capture or daily data access.

## Explain the complete procedure before launch

Ask approval/readiness with a blank TextEdit window prepared. Explain all steps
before starting the clock, including the immediate paused-page inspection below.

1. After launch, choose Start and accept local aggregate consent. Reply when the
   menu shows Collecting; do not enter test keys yet. Confirm actual queue/key
   admission from the current journal before releasing the input instruction.
2. In blank TextEdit, release all modifiers, then press and release left Command
   alone once. This establishes an observed release after capture starts.
3. **Hold left Command down. While still holding it, press A once. Then release
   both keys.** Repeat this entire hold/press/release sequence once more. Do not
   press A after releasing Command. Remain in TextEdit throughout these steps.
4. With the mouse, choose Pause, then immediately Settings > Aggregates and expand
   Exact modifier sides and key code. Do not wait for a second chat instruction
   before opening this page. Report the displayed side/count and TextEdit count,
   or provide a screenshot. Do not Resume. The assistant verifies queue closure
   before interpreting the paused presentation evidence.
5. Request normal Quit after inspection. If the deadline arrives first, retain
   partial evidence; do not reopen automatically or extend collection.

Chinese input instruction to send after Collecting is confirmed:

> 在空白 TextEdit：先单独按下并松开一次左 Command。
> 然后按住左 Command 不放，按一下 A，再把两个键都松开；完整重复这一动作一次。
> 用鼠标点试验菜单的 Pause，接着立即打开 Settings → Aggregates，展开
> Exact modifier sides and key code，告诉我侧别、次数及 TextEdit 次数。

## Expected controls and evidence limits

Expected controls are two key-downs, two key-ups, six modifier callbacks and ten
accepted handoffs. Command alone must add no count. Expected aggregate delta is
two, shortcuts two and bare keys zero. Side reconstruction should show left twice
only if the release and chord sequence were observed without an intervening reset.
Report deviations rather than normalize them away. Preparation counts are attempts,
and journal counters remain non-atomic observations, not raw event traces.

No automatic native-observation retry is part of this round. Manual visible rows
are bounded rendering evidence, not accessibility qualification. This round does
not qualify continuous privacy, complete hosted Keychain lifecycle observation,
an independent lock authority, restart retention or collecting Release.
