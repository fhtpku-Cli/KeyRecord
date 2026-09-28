# Apple Silicon MVP closeout checkpoint — 2026-09-29

Status: offline validation and provisioned trial preparation passed; collecting
MVP still awaits product-host qualification. The preparation below did not launch,
install or register a product App, or operate a real Keychain item, TCC setting,
lock/sleep state or daily statistics store.

## Candidate and scope

Product source tested: `ba57ea711e86de37b92c89c46dc6975b557fa69d`, branch
`codex/phase1-acceptance`, draft PR #17. The accompanying changes add only an
isolated build helper, its plist/entitlement templates, and documentation; they
do not change product Swift source or the normal Xcode project settings.
The primary checkout was not modified. Intel runtime/performance and packet
capture were not part of this work.

## Observed results

| Check | Result | Local evidence |
|---|---|---|
| `Scripts/verify-local.sh --build-only` | PASS: 546 SwiftPM tests; 19 harness CLI cases and 6 offline fixture checks; SwiftPM Release, unsigned universal App Release, native arm64 Debug test build | `.build/verification/run.NXqnQJ/` |
| Hostless App XCTest, selected suites below | PASS: 133 tests, zero failures, zero skips; includes 53 recovery tests and the Release-binary-dependent isolation test | `/private/tmp/keyrecord-closeout-app-tests-20260929.log` |
| `swift test --package-path Spikes/KeychainLifecycle` | PASS: 40 hosted-controller logic tests and 82 preflight tests; injected backends only | `/private/tmp/keyrecord-closeout-keychain-20260929.log` |
| `Scripts/audit-product-network.sh` against the Release executable from the first row | PASS: 1,854 undefined-symbol lines, 20,192 string lines, zero matches, `liveReceipt=false` | Exact binary: `.build/verification/run.NXqnQJ/release/Build/Products/Release/KeyRecordApp.app/Contents/MacOS/KeyRecordApp` |
| Initial signing build through the new helper | BLOCKED: Xcode exit 65, no matching Mac App Development profile; no App launched | `/private/tmp/keyrecord-closeout-script-20260929/build.log` |
| Owner-approved Xcode provisioning follow-up | PASS: matching profile generated, signed arm64 Debug built at `de8b9c526`, existing launcher's signature/profile check passed; no launch | `/private/tmp/keyrecord-mvp-profile-attempt-20260929/build.log` |
| Unsigned build using the new trial templates | PASS: arm64 loader and product dylib; expected bundle ID/display name and Boolean isolation marker | `/private/tmp/keyrecord-closeout-unsigned-trial-20260929.log` and adjacent DerivedData directory |
| Existing launcher `--check` on that unsigned trial | Correctly rejected, exit 2: embedded provisioning profile missing | Trial build above; no launch |
| Build helper CLI | `--help` exits 0; six invalid invocations exit 2 before creating output; existing output is refused; Bash syntax and both plists validate | Commands and cases below |

The package suite totals are Store 173, Measurement 19, Integration 42, Core 233,
Capture 67, Analysis 12. The Integration suite includes the six privacy source
and binary-audit tests with negative fixtures. The App suites are
`LocalKeychainQueriesTests` (6), `Phase1FlowHostlessTests` (14),
`Phase1ReleaseIsolationTests` (22), `ProductLocaleStartupTests` (4),
`ProductLocaleTransactionTests` (3), `ProductRecoveryQuitTests` (53),
`ProductReductionTests` (9), `ProductReleaseBoundaryTests` (11), and
`ProductWiringTests` (11). Expected rejection messages in the boundary fixtures
are not test failures. No native screen or VoiceOver qualification is implied.

Both GitHub macOS build jobs passed for the tested starting commit:
[push workflow](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36468906111)
and [PR workflow](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/36468910969).
Later commits require their own CI results.

## Signing finding and reproducible preparation

A sandboxed `security find-identity -v -p codesigning` returned zero identities.
The same read-only command outside the sandbox found one valid Apple Development
identity. Therefore **a missing certificate is not the established blocker**.
Neither standard local provisioning-profile directory existed. A real Xcode
build requesting the data-protection Keychain entitlements returned:

```text
No profiles for 'com.keyrecord.trial.mvp20260929' were found:
Xcode couldn't find any Mac App Development provisioning profiles matching
'com.keyrecord.trial.mvp20260929'.
```

This agrees with Apple's explanation that the data-protection Keychain access
entitlements must be authorized by a profile: [TN3137](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains).
The owner then approved one attempt, bounded to two minutes, using the existing
Xcode account with `-allowProvisioningUpdates`. That actual attempt exited 0:
Xcode generated `Mac Team Provisioning Profile: com.keyrecord.trial.mvp20260929`,
built the arm64 Debug App and embedded the profile. The signed identifier is
`com.keyrecord.trial.mvp20260929`, Team ID `P3W62C39TN`; the existing launcher's
`--check` passed. This resolves the local provisioning blocker. Runtime Keychain
access is still unverified; no product launch was included in that authorization.

The new helper uses Xcode signing with the requested application identifier,
team identifier and exact Keychain access group. It neither manually re-signs
the finished bundle nor changes the ordinary project defaults. It calls the
existing launcher's `--check` only after a successful build. Its output folder
is new and private; the Info.plist permanently requires explicit trial isolation
on relaunch. It does not pass `-allowProvisioningUpdates`.

From the isolated worktree, after matching signing assets are available:

```sh
bash Scripts/build-isolated-debug-trial.sh \
  com.keyrecord.trial.mvp20260929 P3W62C39TN \
  /private/tmp/keyrecord-mvp-provisioned-next
```

The output path must not already exist and its parent must exist. An optional
fourth argument selects an already installed profile UUID with manual signing.
The actual blocked run used `/private/tmp/keyrecord-closeout-script-20260929`.
The unsigned template check used the same `INFOPLIST_FILE` and
`CODE_SIGN_ENTITLEMENTS` with `CODE_SIGNING_ALLOWED=NO`; that check is deliberately
not exposed as a collecting-candidate option in the helper.

CLI rejection cases exercised: missing arguments, production bundle ID, malformed
Team ID, existing output directory, relative output directory, malformed profile
UUID. Syntax: `bash -n Scripts/build-isolated-debug-trial.sh`; plist validation:
`plutil -lint Scripts/fixtures/isolated-debug-trial/Info.plist Scripts/fixtures/isolated-debug-trial/Trial.entitlements`.
The Bash language server is not installed; no LSP result is claimed.

## Approved first-consent trial and remaining work

The provisioned candidate is at
`/private/tmp/keyrecord-mvp-profile-attempt-20260929/build/Build/Products/Debug/KeyRecordApp.app`,
source `de8b9c526da7606438ace3a78efd5afc5b6c2081`. The general-purpose launcher
alone has no timer. A local bounded controller was therefore compiled from
`/private/tmp/keyrecord-mvp-profile-attempt-20260929/BoundedTrial.swift`.
Its `--check` passed against this candidate and the empty owned 0700 directory
`/private/tmp/keyrecord-mvp-readiness-20260929`; it made no launch. The controller
requests normal Quit at 55 seconds and forced termination of its trial instance
at 60 seconds if needed. The first trial exited before the deadline; the timed
normal-Quit and forced-stop branches were not exercised by that run.

The owner separately approved installation at
`~/Applications/KeyRecord MVP Trial 20260929.app`, first consent/Start with that
private root and the `com.keyrecord.trial.mvp20260929` Keychain namespace, and
only three Command-A shortcuts after Collecting. The installed signature passed;
LaunchServices registration completed. The original trial process produced 32
journal records and a normal Quit summary at the root above. Its accept action
ended with `captureStartDenied(LifecycleCaptureError.runtimeFailed)` and
`permissionStatus=denied`. It never entered Collecting: `sessionCount=0`,
`handoffAccepted=0`, `normalizationOutput=0`, `aggregateDelta=0`,
`flushIssued=0`, and `flushDurable=0`.

First-consent key provisioning and encrypted preferences initialization completed
before that failure: the lifecycle reached capture startup, and the fresh store
contains its encrypted manifest and two encrypted objects. This is product-path
evidence for initial protected storage, not exhaustive Keychain CRUD, lock
accessibility, collected-count durability or lifecycle qualification.

The owner reported the Input Monitoring request, enabled it, and used macOS
Quit and Reopen; the reopened menu said blocked/privacy check. The original
isolated journal had already ended, so it does not identify the reopened
process's failure. Missing isolation environment on OS relaunch is consistent
with the existing fail-closed startup code; it is not another observed `-34018`.
An attempted native AX read failed with `Sky Computer Use native pipe closed
before response`, so no screen or accessibility PASS is claimed. A later process
at the exact installed trial path was found and stopped after the approved
deadline. Whether the OS reopen or the failed UI binding started it was not
established. A subsequent process check found no KeyRecordApp instance.

The controller now has a separately checked recovery mode that reuses only this
known trial root and namespace and writes `privacy-reopen.jsonl` and
`summary-reopen.json`, preserving the first run. It compiled with Swift 6 and
`-parse-as-library`; the standalone SourceKit diagnostic about `@main` lacked
that build mode, while the actual compiler succeeded. `--resume-check` passed
without launching. A new bounded recovery request is pending owner approval;
it does not include further permission changes, lock/sleep or ordinary data.

Still open: real collection and durable restart, current-candidate native consent
and accessibility, permission revoke/regrant, continuous lock/sleep closure and
recovery, exhaustive live product observation for the hosted Keychain controller,
six native ARM resource windows, and qualified Release composition. Release
still uses `BlockedLiveKeychain` and `UnqualifiedCapture`. The final signed
collecting Release must receive its own FR-P1 source/binary audit. These gaps are
not converted to PASS by the tests or the unsigned build above.
