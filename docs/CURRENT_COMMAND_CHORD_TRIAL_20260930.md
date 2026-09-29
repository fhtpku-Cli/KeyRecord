# Explicit Command chord check

Status: prepared, not launched. Fresh owner approval and readiness are required.
The preceding [modifier round](CURRENT_MODIFIER_TRIAL_20260930.md) is preserved.
Its two bare-key counts match the owner's clarified standalone A procedure; it
does not establish a classification defect or complete Command+A acceptance.

## Candidate and isolation

Reuse the installed `~/Applications/KeyRecord MVP Trial 20260929.app`, source
`426969c9f`, bundle ID `com.keyrecord.trial.mvp20260929`. No rebuild, installation
or provisioning update is needed. Whole-bundle `diff -qr` against its signed stage
passes, including the Debug implementation dylib. Performance Trial is untouched.

The new private root `/private/tmp/keyrecord-phase1-chords-live-20260930` is mode
0700 and empty at the no-launch check. The proposed trial Keychain namespace is
`com.keyrecord.trial.mvp20260929.phase1chords20260930`; preparation performed no
Keychain data operation and does not independently prove namespace emptiness.
The approved run would create/read its isolated encrypted store and Keychain only.

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

## Expected evidence, not a recorded result

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
