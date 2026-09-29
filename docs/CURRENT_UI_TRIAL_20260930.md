# Current-candidate UI and attribution check

Status: owner-approved round completed with partial evidence on 2026-09-30.
Current-candidate input, durable-save counters, paused admission and normal exit
were observed. Native row, attribution, rendering and accessibility inspection
remain unverified because the Computer Use connection failed. The preparation
and intended procedure below are retained; this is not a full UI PASS.

## Observed result

The owner explicitly approved this round and confirmed readiness. The prior
installed trial was preserved at `/private/tmp/keyrecord-mvp-before-ui-346dc26d8.app`,
then candidate `346dc26d8` was installed at the planned path and passed the same
no-launch check. The controller launched the exact trial as PID `90634`.
The owner confirmed Start/consent and Collecting. Journal action 32 independently
records granted permission, unlocked readiness, disabled Secure Input, attributable
foreground and actual open queue/key gate. These coarse inputs do not identify
the foreground application in the diagnostic output.

After the separate input instruction, the owner confirmed two left Command-A
presses and Pause. The final summary records two key-downs, two key-ups, four
modifier callbacks, eight accepted handoffs, aggregate delta two, published
shortcut total two and bare-key total zero. All six issued writes returned
successfully and were recorded durable, with zero failed/timed-out/invalidated
writes and zero snapshot-read failures. Before Quit the journal records Paused,
no live capture and the actual queue closed. The key gate remains open while
paused, permitting the intended protected display; this is not a lock-closure test.

The first native UI connection through `cua.getApp` failed with
`Sky Computer Use native pipe closed before response`. No accessibility tree or
rendered trial window was returned. As specified below, a private quit request
ended the round instead of retrying or extending capture. The controller reported
normal Quit requested, exited with `failed=false`, and returned zero. The final
Quit action reported Stopped, no live capture, closed queue and no pending reducer
or scheduler changes. A process check confirmed PID `90634` was gone. The key gate
field is a pre-exit sample; process termination, not that field, establishes that
the trial is no longer running.

Read-only diagnosis found two same-period `SkyComputerUseService` crash reports
in `~/Library/Logs/DiagnosticReports`, named
`SkyComputerUseService-2026-09-30-032326.ips` and
`SkyComputerUseService-2026-09-30-032345.ips`. Both report `EXC_BREAKPOINT` /
`SIGTRAP`, with `_assertionFailure` and `Array.remove(at:)` on the faulting stack.
This corroborates failure of the native observation helper; it does not establish
the exact triggering UI element or constitute a KeyRecord crash. No global tool
configuration was changed and the trial was not relaunched to reproduce it.

### Synthetic observation controls

A subsequent diagnostic used a standalone AppKit fixture with one retained
titled/closable/resizable window and an `NSTextField` reading `Synthetic window
only`. It linked no KeyRecord code and used no capture, store or Keychain APIs.
The same executable was placed in two distinct diagnostic bundles: regular
activation with `LSUIElement=false`, and accessory activation with
`LSUIElement=true`. Both explicitly activated the window and scheduled their own
termination after 90 seconds. Both compiled successfully with Swift 6.4.

After resetting only the Computer Use REPL, `cua.getApp` returned the expected
window and text accessibility tree for **both** bundles. The regular tree also
included a menu bar; the accessory tree did not. Thus the current helper can read
these minimal native windows, and accessory activation alone is insufficient to
explain the product failure. This is not evidence that SwiftUI or the product's
full view hierarchy works. No product App was relaunched, no screenshot was
obtained and no product code or system permissions were changed. The fixture
source/bundles were temporary diagnostic artifacts and were removed after their
processes exited; the live trial evidence above is retained.

The exact failing AX element or helper operation remains unknown. Current crash
metadata identifies helper `26.924.1001281` on macOS `27.0 (26A428)`; both reports
contain an AX observer thread for the trial PID `90634`. This associates the
helper with the trial but does not establish which UI request caused the fault.
Native product row/rendering/accessibility acceptance therefore remains open.

A second pure AppKit control supplied only an accessory status item/menu and no
standard window. `cua.getApp` returned `-10005: timeoutReached`; it did not return
the trial's pipe-closed error. No new matching helper crash report appeared in the
bounded report check. This does not establish the original cause: product Start
itself calls `showWindow()`, and the original trial's actual window state was not
observed. The windowless fixture exited and was removed. Do not infer that opening
a window has already repaired the product observation path.

The current candidate therefore has bounded physical-input/save/pause/quit
evidence. It does not yet have directly observed Command-A rows, TextEdit
attribution, exact modifier provenance, native rendering or accessibility. The
owner's report is retained separately from those missing observations. No second
launch, lock/sleep, permission toggle, performance measurement or daily-store
access was performed. Another round requires separate readiness; preserve the
occupied root and its original artifacts.

## Candidate and isolation

- Source: `346dc26d8` on `codex/phase1-acceptance`.
- Native arm64 signed Debug App:
  `/private/tmp/keyrecord-phase1-ui-candidate-20260930/build/Build/Products/Debug/KeyRecordApp.app`.
- Bundle: `com.keyrecord.trial.mvp20260929`; team: `P3W62C39TN`.
- Proposed install: `~/Applications/KeyRecord MVP Trial 20260929.app`, after
  preserving the existing trial bundle. The Performance Trial is unrelated.
- New empty private root: `/private/tmp/keyrecord-phase1-ui-live-20260930`.
- New exact Keychain namespace: `com.keyrecord.trial.mvp20260929.phase1ui20260930`.
- Build used existing local signing assets with no provisioning update. The
  signature/profile/required-isolation check passed without launch.

The one-round controller source is
`/private/tmp/keyrecord-phase1-ui-controller-20260930.swift`, compiled with
`xcrun swiftc -parse-as-library` to the matching path without `.swift`.
It rejects an occupied root or running same-ID App, verifies the supplied bundle
through the existing trial checker, and launches only with `--run` plus the exact
App path. It requests normal Quit at 175 seconds and stops that trial instance at
180 seconds. An earlier `ui-quit.request` in the private root requests normal Quit.
Unexpected exit does not produce controller success. The timeout/force-stop path
has been compiled and reviewed, not exercised in a live product run.
The final `--check` returned `ready=true launched=false`; compilation succeeded.
Its initial root-path representation rejection was fixed by using the same
standardized Foundation URL handling as the previous controller. Directory
ownership/mode, symlink rejection and empty-root checks remain required.

## Owner interaction

1. Prepare blank TextEdit and confirm readiness before any controller timer starts.
2. After launch, choose Start in the trial menu and accept local aggregate consent.
   Stop on any permission, restart, authentication or Keychain prompt; do not
   change permissions in this round.
3. Once Collecting is independently observed, receive the input instruction.
   In blank TextEdit, release all modifiers, then press left Command-A twice,
   releasing between presses. Use the mouse to select Pause in the trial menu,
   then return to chat and report completion.
4. Inspect the actual native statistics view while paused: Command-A ordinary
   count and exact modifier provenance, TextEdit application attribution, and
   visible paused status. Observe native accessibility labels and the rendered
   target window. Existing source identifiers include `phase2.stat.shortcut`,
   `phase2.stat.application` and the provenance disclosure.
5. Request normal Quit once observation completes; record aggregate/save outcome
   and confirm the exact App process is gone.

The trial can write only its isolated encrypted store/Keychain namespace.
Diagnostics retain coarse state and aggregate counts, with no typed text or
per-event stream. Native UI evidence may include only the trial window containing
these agreed synthetic input aggregates. No lock/sleep, permission toggle,
performance replay, network capture or daily-data access is in this round.

## Evidence and interpretation

Build/check logs:
`/private/tmp/keyrecord-phase1-ui-candidate-build.log` and
`/private/tmp/keyrecord-phase1-ui-controller-check.log`.
Controller output is `/private/tmp/keyrecord-phase1-ui-controller-run.log`.
Runtime outputs are `ui-privacy.jsonl` and `ui-summary.json` under the private root.
They are retained with `ui-quit.request` and must not be overwritten.
Native rows must be observed directly; total counters alone cannot establish
TextEdit attribution, modifier provenance or rendered/accessibility state.
If UI inspection is unavailable, record that part as missing and exit normally.

This round addresses current-candidate UI/attribution requirements. Complete
hosted Keychain lifecycle, independent system-lock authority and a qualified
collecting Release remain open. Existing performance and sleep observations are
retained without rerunning them.

## Completed paused UI readback

The owner explicitly approved this round and confirmed readiness. A fresh
`--check` passed, then the controller launched the unchanged signed candidate as
PID `3080`. The first journal record independently showed Paused,
`expectedCollecting=false`, no live capture, closed queue, open key gate and a
published aggregate. The owner confirmed opening Settings and the aggregate tab.

Binding that exact App again returned `Sky Computer Use native pipe closed before
response`, even after the owner had opened the aggregate page. No native AX tree
or screenshot was returned. The owner was asked to read the shortcut count,
TextEdit attribution and modifier-source detail directly, and replied `2次，是的`.
The owner subsequently confirmed seeing TextEdit (`是的看到了`) after a follow-up
without reopening the App. This supports an owner-observed count of two and visible
TextEdit attribution. The exact left/right Command source detail was not explicitly
confirmed. Do not infer exact modifier provenance or full UI/accessibility
acceptance from those replies.

The controller requested normal Quit at its configured deadline and returned
`exited=true quitRequested=true failed=false` with exit code zero. An exact process
check confirmed PID `3080` was gone. All five journal records had no live capture
or open queue. Final summary: zero key-down/up/modifier callbacks, zero accepted
handoffs, zero aggregate delta, zero issued writes and zero snapshot-read failures;
published totals were two shortcuts and zero bare keys. It recorded one aggregate
publication and four analysis-model publications, not four observed screen paints.
The final Quit action reports prior phase Paused, final Stopped, no unsaved reducer
or scheduler data and no lifecycle flush required.

This provides current-candidate paused persistence/readback evidence without new
input. Native rendered row/provenance and accessibility verification remain
limited as above. Existing trial files remain intact; the readback output names
are now consumed, and this controller must not automatically relaunch the round.
The controller's unexpected-collection watchdog was not exercised by this run.

### Retained preparation and procedure

To avoid repeating physical input, a separate one-use controller can reopen the
unchanged installed candidate against this round's existing isolated store and
Keychain namespace. The installed executable compares equal to the staged signed
candidate. The preceding final Quit record has `expectedCollecting=false`, closed
queue, prior phase Paused and normal termination decision. The new controller
requires those facts and unused output names, then repeats the existing bundle,
private-root, symlink, same-ID-process and signature checks. Its compiled `--check`
returned `ready=true launched=false priorPaused=true`.

Source: `/private/tmp/keyrecord-phase1-ui-readback-controller-20260930.swift`;
executable: the same path without `.swift`. Compilation uses `-parse-as-library`.
`--check` and `--run` both require the exact installed App path as their second
argument. The normal Quit/deadline remain 175/180 seconds. New evidence filenames
are `ui-readback-privacy.jsonl` and `ui-readback-summary.json`; the separate
`ui-readback-quit.request` can end the round early. Original evidence is not
overwritten. Any observed live capture, open queue or Collecting phase in the new
journal triggers termination and records failure. This watchdog is reactive; it
is not a replacement for the product's persisted stopped intent. The launch and
watchdog branch was prepared; the normal launch/quit path is now observed above.

Wait for the owner's approval and readiness before `--run`. Then:

1. Verify the restarted trial stays stopped/paused and does not collect.
2. Ask the owner to open the trial menu, choose Settings, then select the aggregate
   tab in its main window. Do not choose Start/Resume or type test input.
3. Inspect the current aggregate rows, TextEdit attribution and modifier provenance
   using native observation. If the helper fails again, request the owner's direct
   description or a screenshot limited to this trial window; do not relaunch.
4. Stop immediately on permission, authentication, restart or Keychain prompts.
   Finish with normal Quit and check for no remaining exact trial process.

This round may read the existing trial Keychain/encrypted store and write new
diagnostic outputs. It does not access the daily store or intentionally collect
new input. It cannot complete the independent lock-authority or full hosted
lifecycle requirements. Preparation alone authorizes no launch.

## Prepared manual provenance readback (not run)

The remaining owner-observable detail is the exact modifier variant under the
shortcut's disclosure group. The current view source labels this control
`精确修饰键侧别与键码` / `Exact modifier sides and key code`; each expanded variant
shows its exact chord and source counts. The preceding replies confirm two
occurrences and TextEdit, but do not confirm this expanded detail.

A separate controller is prepared at
`/private/tmp/keyrecord-phase1-ui-provenance-controller-20260930.swift`, compiled
with `swiftc -parse-as-library` to the same path without `.swift`. Its `--check`
completed with `ready=true launched=false priorPaused=true`. It retains the
175-second normal Quit / 180-second exact-instance stop bound, the same installed
signed `346dc26d8` candidate, private root and Keychain namespace. A byte comparison
confirmed the installed executable still matches the retained signed candidate.
The later deletion fixes are not installed by this procedure.

This controller requires the completed readback's final paused Quit record and
summary: two published shortcuts, no new input/handoffs/aggregate delta/writes,
no snapshot-read failure and no privacy-journal write failure. It refuses occupied
new outputs (`ui-provenance-privacy.jsonl`, `ui-provenance-summary.json`,
`ui-provenance-quit.request`) and retains the existing reactive unexpected-capture
watchdog. Compilation and the no-launch check do not verify that watchdog's
runtime stop branch. All earlier evidence remains untouched.

After fresh approval and readiness, launch once, confirm paused/closed admission,
then ask the owner to open Settings > Aggregates and expand the shortcut's exact
modifier detail. Record the displayed modifier side and count, or the actual
different/missing text. Do not ask for test input or Start/Resume. Stop on any
permission, authentication, restart or Keychain prompt. Request normal Quit as
soon as the report arrives and verify final counters and exact process exit.
This manual round avoids another failing native-observer attempt; it cannot
establish accessibility behavior, an independent OS lock witness or full Release
qualification. No launch has occurred and no result is recorded for this round.
