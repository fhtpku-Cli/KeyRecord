# Apple Silicon collecting candidate

Status: product Release dependencies and the Phase 1 surface pass offline validation.
Source `ea90753feab2358166ee39384bb6a5501dc4ce64` is now signed and installed as
`~/Applications/KeyRecord Release Trial.app`, but has not been launched or exercised
with real input. Public distribution and PR merge remain outside this work.

The Release composition uses the same exact-item Security backend and query
builders already measured in the signed product cases. Only its DEBUG read
instrumentation remains conditional. Non-synchronizable data-protection items,
device-only accessibility, authentication-UI refusal, exact account queries and
all product privacy/recovery checks remain intact.

Immutable capture qualification permits only the existing observed native arm64
macOS 27.0 build 26A428 candidate. Unsupported platform reads select the blocked
backend and an unknown lock provider. Release has no developer environment/defaults
arming path. The same observed provider reaches product readiness and the event
source, including synchronous notification closure and stale-startup rejection.

Default Keychain namespace and App Support directory derive from the same validated
Bundle ID. Missing, empty, malformed and path-traversal identities are rejected;
there is no fallback to `com.keyrecord.app`. That ordinary app identity retains its
original location. Explicit DEBUG trial selection still excludes the fixed daily
`com.keyrecord.app/store` path and its parent/child overlaps independently of the
trial's own default identity.

Validation: native arm64 unsigned Debug and Release builds pass; 127 selected App
tests pass in 75.322 seconds, including factory support/identity isolation, malformed
identity refusal, daily-root exclusion, exact Keychain query properties, recovery
and destructive Release capability mutations. Six core trial-isolation tests pass.
The actual Release project/bundle audit reports one executable, no helpers or
forbidden developer/test tokens; the static network audit reports zero matches.
The audit now permits the two deliberately promoted Keychain implementation types;
all other restrictions and the default Universal architecture mode remain intact.

Build/test logs: `/private/tmp/keyrecord-release-integration-debug-build.log`,
`/private/tmp/keyrecord-release-integration-release-build.log`,
`/private/tmp/keyrecord-release-integration-app-tests.log` and
`/private/tmp/keyrecord-release-integration-trial-isolation-tests.log`.

The MVP surface now uses the existing Phase 1 aggregate view. Recommendation
controls, menu suffix and badge are absent; Phase 2 implementation is retained.
Ten focused native UI/modifier tests pass, including real ProductScreens tab
activation, English/Chinese totals and removal of all rows when the snapshot is
cleared. Both rendered locale images were inspected. These use synthetic data,
not live capture. The view labels keys numerically and applications by Bundle ID.
Debug/Release builds and the final Release static audits pass again.

Native evidence: `/private/tmp/keyrecord-mvp-surface-native-final.log` and
`/private/tmp/keyrecord-mvp-ui-output/product-aggregates-{en,zh-Hans}.png`.
An initial unchanged window-teardown test threw an AppKit transition exception;
it passed subsequent runs without a product change. New test fixture corrections
select the native window toolbar tab, set the requested locale and give only the
test screenshot an opaque background. Assertions retain actual before/after UI
postconditions rather than relying on AXPress's inaccurate return status.

## Signed local candidate

The actual Release product uses the already provisioned
`com.keyrecord.phase1.probe.host` identity and existing Apple Development certificate
for team `P3W62C39TN`. This is the product app, not the hosted XCTest probe.
The exact embedded profile UUID is `01e3da0d-8706-4ed6-8234-4747a5bf9b9d`, expiring
2026-10-07 09:39:57 UTC. Application identifier and its sole Keychain access group
are `P3W62C39TN.com.keyrecord.phase1.probe.host`. Hardened runtime is enabled;
development signing also grants get-task-allow, so this is not a public distribution
artifact. No provisioning update was requested.

The first build stopped normally in 6.876 seconds because Xcode-managed profiles
cannot be selected with Manual signing. Switching to Automatic selection of existing
material resolved that configuration error. The corrected build exited normally in
29.989 seconds with no remaining build process group. Strict signature verification,
actual embedded-profile comparison, arm64 capability audit and static network audit
all pass. The product has one executable, no helpers, no forbidden developer tokens
and zero network matches. Static audit output says unsigned-build-only by convention;
signing evidence comes from the separate codesign/profile checks. Installed main
executable compares equal to the staged signed executable and its signature passes.

Evidence: `/private/tmp/keyrecord-release-candidate-fixed-20261001/{build.log,result.json}`.
The failed attempt remains under `/private/tmp/keyrecord-release-candidate-20261001`.
Independent signing review: `/private/tmp/.omo/evidence/release-candidate-signing-review.md`.

This identity defaults to `~/Library/Application Support/com.keyrecord.phase1.probe.host/store`
and the same exact Keychain service. The parent directory was absent before installation;
no Keychain query has been made, so exact service emptiness is unverified. Existing
UUID-scoped probe fixtures do not use this service by construction. A collision must
stop under existing product checks; do not delete or adopt pre-existing items.
Do not copy the old MVP store or reuse its keys. No temporary home or developer
environment override will be used. A new Input Monitoring permission may be needed.

Next: stop for owner readiness and the new identity's permission, then run one short
Start/consent, two left Command-A inputs, Pause and native aggregate/side/count check.
The new Phase 1 view represents A as Key 0 and TextEdit as com.apple.TextEdit, and
shows modifier side directly in the row. No detail disclosure is required. Do not
repeat completed physical lock, sleep, short performance or FR-P7 rounds.

Prepared controller: `/private/tmp/keyrecord-release-input-round-20261001.py`,
with compiled `/private/tmp/KeyRecordReleaseQuit` (`.swift` alongside). It starts
the installed main executable directly, retains that child PID/session, and uses
the native application termination path for normal Quit. SIGINT/SIGTERM request
the same cleanup. Continuous time limits normal Quit to 175 seconds and force to
180; controller cleanup reports by approximately 182 seconds. Its one-use output
directory is `/private/tmp/keyrecord-release-input-round-20261001`. The earlier
asynchronous `KeyRecordReleaseTrialControl.swift` prototype is rejected and unused.
Four synthetic normal/stop/force/error paths pass independent review. The installed
candidate's controller `--check` passes with zero competing identity processes;
this mode performs no launch or Keychain query. An operator stop or a zero controller
exit alone is not acceptance evidence. Actual input/UI observations remain required.

Package regression follow-up: remote CI on `ea90753f` exposed two stale source
tests requiring the promoted backend/query builder to remain DEBUG-only and the
composition to remain universally unqualified. Those obsolete assertions are
removed; unique-adapter, exact-query, blocked fallback, no-network and no-shell
checks remain, alongside the App factory's supported/unsupported behavior tests.
The ten affected-group tests pass and the complete local SwiftPM suite passes
591 tests with zero failures. Logs: `/private/tmp/keyrecord-release-package-boundary-tests.log`
and `/private/tmp/keyrecord-release-package-all-tests.log`. This follow-up changes
only tests/docs; signed product source remains `ea90753f`. Updated remote CI is
pending and must not be represented as passing from local results.
