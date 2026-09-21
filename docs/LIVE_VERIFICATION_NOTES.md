# Live verification notes

Constraints and environment facts for running KeyRecord on a real Mac. These are not status
claims and grant no acceptance: they exist so a host run measures what it claims to measure.
The remaining executable and owner-assisted work is in [PHASE1_ACCEPTANCE.md](PHASE1_ACCEPTANCE.md).
Current status is in [PROJECT_STATUS.md](PROJECT_STATUS.md); behavioral requirements are in
[PHASE1_CONTRACT.md](PHASE1_CONTRACT.md).

## What a bounded run may do

Capture is keyboard monitoring, so a host run is bounded by construction, not by convention:

- Fixed duration, normally 30-60 seconds, with an unconditional self-stop. Owner-approved
  multi-step lifecycle trials used a 170-second normal quit request and a 180-second
  forced-stop limit. This runner uses uptime, so system sleep can extend wall-clock duration.
- Record **layered counts and coarse state only**. Never input text, never raw key
  sequences, never per-event timestamps.
- Never modify TCC, disable Karabiner, write to the real keychain, lock the screen or
  restart the machine without explicit owner authorization for that specific run.
- Verify exactly one instance is running (`pgrep -x KeyRecordApp`) before launching. Two
  instances sharing one bundle id and one store violates the single-writer rule, and a stale
  instance also means the menu being read may belong to an older build.
- Hash the real store before and after, and compare. A run that intends to touch nothing
  must be able to prove it touched nothing.

## Isolation

`CFFIXED_USER_HOME` redirects `applicationSupportDirectory`. `HOME` alone does **not** —
setting only `HOME` leaves the app writing to the real store.

`CFFIXED_USER_HOME` **also isolates the keychain**: under an isolated home,
`Library/Keychains/` does not exist and every `SecItemCopyMatching` returns
`errSecItemNotFound`. Consequences:

- An isolated run cannot read the real master key, so the store bootstrap legitimately fails
  with `envelopeKeyMissing`. That is fail-closed working correctly, **not** a product defect.
- Tests that must exercise real keychain reads cannot use this isolation.
- Tests that need to **write or delete** keychain items need a separate mechanism (a
  dedicated keychain file or a distinct bundle id); this isolation is not sufficient.

Every directory in the isolated path must be `0700`. `preparePrivateRoot` rejects anything
looser, and the app then falls back to its minimal error menu.

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

**Unlock and wake do not automatically resume collection.** The current explicit recovery
entry is the menu-bar KeyRecord **Start** action. The consent page has no retry button.
After recovery, record the existing counts before entering another test shortcut. A hidden
aggregate panel alone does not identify which privacy condition closed it.

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

- Xcode places the code in `KeyRecordApp.debug.dylib`; the main binary is a loader. Scanning
  only the main binary makes a current build look like a stale one.
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
- Adding `ProductComposition.swift` to a test target pulls in the whole composition graph and
  fails to compile. Extract pure functions into Core instead.

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

## Remaining host qualification

A→B foreground transitions, Local Capture Off, permission changes, user switching, continuous
privacy-boundary evidence, signed Release acceptance, real-keychain writes and ARM + Intel
performance still need qualification. Older bounded exclusion and sleep/wake observations
exist; they do not qualify the full matrix or the current candidate. G1 remains **BLOCKED**.
