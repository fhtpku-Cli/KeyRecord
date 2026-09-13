# T23: Release boundary qualification

## Outcome boundaries

Static qualification is PASS. Signed product/host qualification remains **BLOCKED/2**.
Neither Q23 nor a successful unsigned Universal build proves a developer signature,
Team ID, signed entitlements, Keychain behavior, a fresh launch, or hosted UI behavior.
The plan's full task 23 and G1 gates are not complete.

`ProductReleaseBoundaryTests` is an App XCTest suite executed directly, not hosted
inside KeyRecordApp. `Scripts/task23-qa.sh` builds Release with
`ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO`, then builds
the separate Debug test bundle. The Release app is never launched by this channel.

`Scripts/release-boundary.rb` checks:

- Actual `lipo -archs` is exactly arm64 + x86_64; `nm` runs on both slices.
- Every final bundle file is scanned as bytes and with `strings -a`; plist,
  entitlements and localized strings are also decoded with `plutil`.
- Known DEBUG composition/provider/controller symbols, fake types, fixture/QA
  environment tokens, XCTest/XCUITest, test support and task QA scripts are absent.
  Standard runtime debug-description symbols and lowercase `flowpreview.tab.*`
  localization keys used by the real product are not test-only capabilities.
- `Contents/MacOS` contains exactly the executable KeyRecordApp. Other executable
  files, symlinks, embedded test bundles/frameworks/plugins, XPC/extensions,
  login helpers, HelperTools and launch agents/daemons are rejected.
- Parsed PBXNativeTargets contain exactly one non-test product: KeyRecordApp app.
  CLI, extension, XPC and extra app products, legacy/aggregate targets and custom
  execution/copy phases are rejected. This is a structural process-boundary check,
  **not an observed runtime spawn count**.
- Release source build phases and root library sources are scanned after removing
  inactive DEBUG blocks with `unifdef`; spawn/shell/network/CLI APIs are forbidden.
- Release settings retain hardened runtime and the non-sandboxed contract;
  the configured Info.plist and built Info.plist require LSUIElement=true.
  Configured entitlement files must exist and parse. Network, device, file-access,
  temporary-exception, personal-information, automation and code-signing exception
  entitlement keys are rejected in source/configuration and decoded bundle files.

Failure fixtures mutate fresh copies of the actual app or isolated project metadata.
They reject fake tokens, extra executables (even without execute permission), XCTest,
QA scripts, network entitlements, CLI targets, missing configured entitlement files
and malformed project input. Their expected checker exit is 1; passing rejection
tests have XCTest exit 0. Copies are removed by test teardown.

## Reproduce in an isolated worktree

Choose a new absolute attempt directory; the runner refuses reused case receipts.

```sh
A="$PWD/.omo/evidence/repository-status-next-step/t23-attempt-$(date -u +%Y%m%dT%H%M%SZ)"
bash Scripts/phase1-qa.sh task 23 happy --attempt "$A"
bash Scripts/phase1-qa.sh task 23 failure --attempt "$A"
bash Scripts/phase1-qa.sh host signed-build --manifest "$A/host.json" --attempt "$A"
```

Q23 happy requires 2 tests; failure runs all 10 tests including the positive controls.
Both allow zero skips only. The host command returns BLOCKED/2 and preserves private,
attempt-local identity inventory, codesign output and tool exit statuses. Raw host
receipts must not be committed. No runner classification logic was changed.

## Signed-host recovery conditions

`phase1-signed-build-host.sh` is deliberately a read-only blocked entry point,
not an implemented authorized host controller. It never imports/creates certificates,
unlocks a keychain, signs, changes a Team ID, grants permissions, invokes hosted tests,
or launches the app. Supplying a manifest alone cannot turn it into PASS.

Recovery requires all of:

1. Explicitly authorized internal Apple Developer Team ID and matching existing
   certificate/private key, with the intended internal bundle identity. A certificate
   merely appearing in `security find-identity` is **not authorization**.
2. A private, unexpired host manifest satisfying plan contract 3: actual host/OS/arch,
   certificate fingerprint/Team/bundle IDs, permitted test namespace and scratch root,
   operation allowlist and approved noninteractive controller hash. Implement and
   qualify that controller before any signed-host effect.
3. A genuine signed Universal build, strict codesign verification, inspection of
   actual entitlements/Team/hardened runtime and fresh signed-product launch.
4. Authorized KeyRecordAppUITests: T18 Phase1FlowTests all seven flows, plus T22
   system accessibility settings, Full Keyboard Access/Tab, VoiceOver and real screen
   edges. Direct XCTest does not discharge these retained checks.
5. Observe the fresh product process tree with spawn count=1 on the supported
   minimum-macOS/Intel/Apple Silicon host matrix. Deployment-target and lipo checks
   do not prove runtime compatibility on those hosts.
6. Retain the signing/archive pipeline's notarytool/stapler checkpoint. Current
   preflight only discovers these tools; no upload, stapling or public distribution.

## Local verification record

Attempt: `.omo/evidence/repository-status-next-step/t23-attempt-20260913T225327Z`
(private, uncommitted), baseline `064164e`, lane `feat/phase1-t23-signbound`.

- `task-23/happy`: PASS, 2 executed, 0 skipped, child exit 0.
- `task-23/failure`: PASS, 10 executed, 0 skipped, child exit 0.
- Release: arm64 + x86_64, two nm scans, five bundle-file scans, zero forbidden
  tokens, one executable, zero helpers; 91 Release/product-library source files.
- `full-root.log`: 350 tests, zero failures. `runner-regression.log`: 39 tests,
  zero failures. Build/direct XCTest supplies Swift compiler validation; this
  execution environment does not expose an LSP diagnostics tool.
- `host/signed-build`: BLOCKED, zero tests, child exit 2. Strict codesign verification
  exited 1; display showed linker ad-hoc signature, TeamIdentifier not set,
  Info.plist not bound, and no sealed resources. Display exit 0 is not validation.
- Identity inventory unexpectedly found an existing development identity; it was
  not used or treated as authorized for this product. No identity details are
  published here. notarytool/stapler discovery succeeded, without invoking either.

No production source, entitlement, Team setting, host permission, historical evidence
or plan checkbox was changed. Static PASS must not be promoted to signed-release PASS.
