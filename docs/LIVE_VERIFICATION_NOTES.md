# Live verification notes

Constraints and environment facts for running KeyRecord on a real Mac. These are not status
claims and grant no acceptance: they exist so a host run measures what it claims to measure.
Completed MVP evidence and limits are in [PHASE1_ACCEPTANCE.md](PHASE1_ACCEPTANCE.md); no repeat host round is pending.
Current status is in [PROJECT_STATUS.md](PROJECT_STATUS.md); behavioral requirements are in
[PHASE1_CONTRACT.md](PHASE1_CONTRACT.md).

**Applicability — 2026-10-01:** PR #17 is merged and the scoped Apple Silicon
Phase 1 objective is complete. Release uses the real exact-item Keychain backend
on native arm64 macOS 27.0 build 26A428; other platforms fail closed.
See [the signed candidate](RELEASE_CANDIDATE_20261001.md). Historical Debug home,
store and namespace instructions must not be copied into the Release launch.

## What a bounded run may do

Capture is keyboard monitoring, so a host run is bounded by construction, not by convention:

- Agree a duration appropriate to the steps before launch. Recent Release rounds use a
  continuous clock: normal Quit at 175 seconds and exact-instance force at 180 seconds.
  Older uptime-based controllers can extend across sleep; do not describe them as
  wall-clock bounds or reuse consumed output paths.
- Record **layered counts and coarse state only**. Never input text, never raw key
  sequences, never per-event timestamps.
- Never modify TCC, disable Karabiner, write to the real keychain, lock the screen or
  restart the machine without explicit owner authorization for that specific run.
- Verify that the exact trial instance is absent before launch and exactly one exists
  afterward. Match the bundle/executable path as well as the process name; similarly
  named trials are not interchangeable. Two instances sharing an identity/store violate
  the single-writer rule, and a stale instance can expose the wrong build's menu.
- Limit observations to the approved isolated store and scenario. Use existing counts,
  transaction results and targeted tests; do not access the daily store or add new
  hashes/baselines merely to document a read-only or UI round.

## Isolation

The Release candidate derives native App Support and exact Keychain service from its
validated Bundle ID. It uses no developer arming variables or HOME/CFFIXED_USER_HOME
override. Preserve the isolated identity across planned updates.

Historical opt-in Debug trials used **both** `KEYRECORD_TRIAL_STORE` and
`KEYRECORD_TRIAL_NAMESPACE`; see [the historical protocol](PRIVACY_RESOURCE_PREP.md).
The store path is explicit and the exact Keychain service/account namespace is test-only.
Do not point at production statistics or reuse a production namespace.

Do not override `HOME`/`CFFIXED_USER_HOME` for this traditional-file-Keychain path.
In the PR #10 host round, a temporary home made default-Keychain lookup fail and
Accept presented a missing-Keychain dialog. Normal user environment lookup succeeded.
Cancel that dialog rather than resetting the default Keychain. The corrected trial
retained explicit store/namespace isolation and completed the bounded run.

Historical home redirection isolated Application Support but was not a working
provisioned Keychain setup. It does not guarantee every SecItem operation returns
item-not-found. Namespace isolation is not a separate Keychain file; use only the
approved test identity, and never infer permission to change user Keychain settings.

Keep the owned trial root private (0700) and store files 0600. Follow that candidate's
path validation; do not change permissions on shared ancestors such as /private/tmp.

## Measurement traps

Each of these produced a wrong conclusion at least once.

**A control run must share the environment of the thing it tests.** Running
`security find-generic-password` in a shell without the isolation variables and concluding
something about an isolated app is invalid — the same probe returns "found" in one
environment and `errSecItemNotFound` in the other.

**Zero events observed while nothing was typed is not evidence.** It is the absence of
input. Any claim that events are being dropped requires a run where input demonstrably
occurred.

**The counters are gauges only when something writes them.** The repaired DEBUG product
wires the per-layer hooks and marks instrumentation explicitly. Earlier builds did not;
an unwritten zero previously yielded a fabricated finding. Per-session counters reset
when capture is prepared again, so returning from another app can hide earlier activity.
The opt-in `KEYRECORD_DIAGNOSTIC_SUMMARY_PATH` writes a process-lifetime numeric JSON summary
on normal termination. Use a fresh private output path for each approved run; missing output
is not success. It retains last successful model-publication totals without reading the
protected store during shutdown. Positive totals cannot attribute a particular keypress,
and publication is not proof of rendering.

**Identical titles need not mean identical groups.** Aggregation retains modifier sides and
unknown states. The current display names these distinctions; older titles collapsed them.
Compare all relevant rows and before/after totals, not one matching label.

**The first modifier side after recovery can legitimately be unknown.** Queue reset forgets
held sides. A family-active flagsChanged event alone cannot distinguish pressing one side
from releasing that side while its opposite remains held. Observe a released state first,
then a fresh press in the same foreground session when testing side reconstruction. Do not
infer side identity from which physical key the tester intended to press or preserve old
side state across a privacy/session boundary.

**Recovery is state-dependent.** Fresh privacy/key checks and persisted collecting
intent govern restart/recovery; never override user pause. Completed lock/sleep
rounds observed stopped states followed by explicit Start. Release readback opened
Paused; its cause was not established. Neither proves all unlocks/wakes/restarts
always pause or always resume. Record the actual menu state and use its available
Start/Resume only within the approved scenario. A hidden panel alone does not
identify the closing privacy condition.

**A dark screen does not prove system sleep.** Compare the trial interval with system
sleep/wake records. Leave sleep-prevention settings unchanged unless separately authorized.

**End host trials through normal App termination.** Request AppKit termination for the
identity-checked trial process, then verify its exit and summary receipt. SIGTERM can bypass
the termination receipt. The forced-stop fallback is not evidence of successful saving.
For exclusion tests, record the original switch state and restore it, or obtain the owner's
desired final setting. Compare the tested application's groups, not global counts affected
by screenshots or other applications. Never start another host trial merely to fill an
evidence gap without renewed approval.

**Boot-time samples go stale.** Fields captured once during startup (armed, lock state,
whether the key gate was open) describe that instant. Rendered without that label, a lock
that has since been released still reads `locked`.

## Tooling facts specific to this project

- The Debug builds described here put product code in `KeyRecordApp.debug.dylib`;
  their main executable is a loader. Inspect the actual build layout. The signed
  Release has one main executable; do not assume it has a Debug dylib.
- `strings` not finding a symbol name proves nothing; use `nm` against the symbol table.
- `pgrep -f` matches its own command line and inflates counts. Use `pgrep -x`.
- `sample` showing no event-tap frame does not mean there is no tap; an idle tap does not
  appear on an active stack. `lsof` cannot see a CGEventTap at all — it is a mach port, not
  a file descriptor.
- Native Debug test compilation uses `ARCHS=<native architecture> ONLY_ACTIVE_ARCH=YES`.
  For universal Release, use the fresh derived-data workflow in `Scripts/verify-local.sh`;
  the earlier x86_64 failure described a build using arm64-only modules, not a permanent
  inability to build a universal App. Compilation is not Intel runtime qualification.
- macOS has no `timeout` command.
- New App-layer sources must be registered by hand in `KeyRecord.xcodeproj/project.pbxproj`
  (PBXFileReference, PBXBuildFile, sources phase, group children); validate with
  `plutil -lint`. The project uses explicit file references, not synchronized groups.
- The App test bundle does not link `KeyRecordTestSupport`.
- App XCTest now includes product composition and its dependencies. Earlier missing-
  dependency failures do not prohibit these tests; preserve target wiring and separate
  pure model checks from authorized live-host tests.

## Release isolation

Diagnostics are DEBUG-only. Unit tests cannot detect a leak into Release, because a test
bundle is always built DEBUG. Any change to diagnostics must be followed by a Release build
and a symbol scan (`nm -U`) confirming zero diagnostic symbols. An earlier revision leaked
157 of them and passed every test.

## Recorded host observations

Historical facts reported on the owner's machine with the earlier signed Debug candidate.
They describe that machine at that time, not current-main qualification. The exact scope
and later bounded trials are recorded in [PROJECT_STATUS.md](PROJECT_STATUS.md).

- A 45-second run with all four Karabiner daemons active saw tap keyDown 168 / keyUp 168,
  queue accepted 336, normalized 336, aggregate delta 168, zero closed handoffs and zero
  tapDisabled. This refutes complete event swallowing before that harness during that run;
  it does not identify a product failure's cause or exclude intermittent Karabiner interactions.
- Bounded lock trials observed closed/recovery states and later manual Start recovery.
  This does not establish continuous zero capture during the locked interval; fresh-check
  and generation-fence behavior also has separate synthetic regression coverage.
- `CGPreflightListenEventAccess()` reports granted, unchanged across runs. TCC.db is
  SIP-protected and cannot be read.

## Qualification limits after Phase 1

The scoped MVP is complete; dated observations above are not a new follow-up queue.
See [current acceptance](PHASE1_ACCEPTANCE.md) for measured candidates and retained
limits. General macOS/Intel support, exhaustive user-switch/assistive-technology
matrices, actual system login-unregistration measurement, public distribution and
FR-P6 are not newly established by these rounds. Do not repeat completed
lock/sleep/performance/Keychain cases or claim full G1/v1 completion.
