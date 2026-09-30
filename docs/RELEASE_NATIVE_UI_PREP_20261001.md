# Remaining signed-host native UI check

Status: prepared, not executed. This closes the existing T23 scope in
[DESIGN](DESIGN.md), not a new product requirement. Native matrix/AX tests and the
two live aggregate screenshots retain their separate evidence scopes.

Use unchanged signed `ea90753f`, installed as KeyRecord Release Trial. Its latest
owner-observed restart was already Paused and recovered both TextEdit records.
No Start/Resume, new capture input, reset/delete or login-item toggle is requested.
If the next launch is not Paused, immediately request normal Quit through the
reviewed exact-PID helper and report it. Do not perform keyboard or VoiceOver
navigation first. Do not infer capture admission from the static screenshot.

## Prepare before the bounded launch

The owner must be ready for system accessibility controls and audible VoiceOver.
Record the original keyboard-navigation, VoiceOver, Increase Contrast and Reduce
Motion settings. With the trial closed, enable the settings needed for this check.
Preserve the originals for restoration; an already-enabled option must not be
switched off as cleanup. Do not use defaults writes or undocumented system APIs.
If a control is unavailable or prompts for authentication, stop and report it.

The prepared controller `/private/tmp/keyrecord-release-native-ui-round-20261001.py`
reuses the reviewed exact-child supervision and normal-quit helper. It has a fresh
one-use output root of the same name without `.py`, normal Quit at 175 seconds and
force at 180 seconds. `--check` performs no launch or Keychain query. Invoke `--run`
only after fresh owner readiness; the script does not wait for that confirmation.
Setup time is outside this bounded App process lifetime.

## Observe while Paused

1. Open the real status-item menu. Check the status and action labels are readable
   and the menu stays on the actual screen; retain the visible menu location and
   report any clipped item. Do not claim all monitor arrangements from one screen.
2. Open Settings. Use Tab forward and Shift-Tab backward through the enabled
   controls and endpoints. Report skipped/unreachable controls, invisible focus
   or a focus trap. Do not activate reset/delete, login, exclusion or capture actions.
3. With VoiceOver enabled, traverse the aggregate and settings controls. Confirm
   the labels, values and selected/disabled states are intelligible; report an
   unlabeled control or an incorrect state rather than treating any speech as PASS.
4. With the actual system Increase Contrast and Reduce Motion settings enabled,
   inspect text/focus visibility and switch between Settings and Aggregates.
   Report clipping, unreadable labels or unexpected product animations. Record the
   actual switch states; requested fixture appearances alone are insufficient.
5. Verify the aggregate remains total 2 / bare 0, with TextEdit unknown Command 1
   and left Command 1. Report the actual result, including any unexpected change.
   The controller normally quits early after the observations, or at its deadline.

Restore the original system accessibility settings after the App is closed, whether
the round succeeds, times out or is aborted. Leave originally enabled options enabled.
If setup or the sequence does not fit, preserve partial observations and stop;
do not silently extend the deadline or automatically reopen. Operator feedback
establishes this bounded walkthrough, not universal assistive-technology support.
