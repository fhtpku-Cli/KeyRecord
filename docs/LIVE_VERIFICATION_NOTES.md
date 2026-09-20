# Live verification notes

Constraints and environment facts for running KeyRecord on a real Mac. These are not status
claims and grant no acceptance: they exist so a host run measures what it claims to measure.
Current status is in [PROJECT_STATUS.md](PROJECT_STATUS.md); behavioral requirements are in
[PHASE1_CONTRACT.md](PHASE1_CONTRACT.md).

## What a bounded run may do

Capture is keyboard monitoring, so a host run is bounded by construction, not by convention:

- Fixed duration, 30-60 seconds, with an unconditional self-stop.
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

**The counters are gauges only when something writes them.** The per-layer counters in
`CaptureDiagnostics` are incremented by the harness and by unit tests, not by the shipping
app. An unwritten zero read as a measurement previously yielded the fabricated finding that
no keyboard event had reached the process.

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
- `xcodebuild` needs `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`; the x86_64 slice does not build
  here because the SwiftPM modules are arm64-only.
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

Facts established on the owner's machine. They describe that machine at that time.

- Karabiner's DriverKit layer does **not** swallow physical key events: a 45-second run with
  all four daemons active saw tap keyDown 168 / keyUp 168, queue accepted 336, normalized
  336, aggregate delta 168, zero closed handoffs, zero tapDisabled. The earlier suspicion is
  disproved; disabling Karabiner as a control adds nothing.
- Lock and unlock behave per contract: locking closes the gate, revokes and stops capture and
  enters a failed phase; unlocking rebuilds the session only after fresh checks pass.
- `CGPreflightListenEventAccess()` reports granted, unchanged across runs. TCC.db is
  SIP-protected and cannot be read.

## Still unverified on a host

A→B foreground attribution, exclusion changes, Local Capture Off, sleep/wake, signed Release
acceptance, real-keychain writes, and the ARM + Intel performance matrix. All remain
**BLOCKED**, not passing.
