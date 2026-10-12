# KeyRecord

KeyRecord is an in-development native macOS menu-bar app for local, aggregate keyboard-use statistics. It aims to count shortcuts by application and bare keys without storing typed text or event sequences. The codebase uses Swift 6, macOS 14+, and Apple system frameworks.

**Current stage (2026-10-01): scoped Apple Silicon Phase 1 complete and merged.** [PR #17](https://github.com/fhtpku-Cli/KeyRecord/pull/17) merged into main as `8bb99e81a6ea411c5e167e156a548372e961c44d`; merge-commit CI passed. The development-signed Release candidate completed real shortcut capture, encrypted save/reopen readback and a bounded native UI walkthrough. Keychain, lock/startup/recovery and short ARM performance results retain their documented candidate scopes. This is not full G1/v1, Intel, general macOS support or public distribution qualification.

Capture permits only measured native arm64 macOS 27.0 build `26A428`; other platforms remain closed. The trial uses `com.keyrecord.phase1.probe.host`, separate from daily data; its development profile expires on 2026-10-07 at 17:39:57 Asia/Shanghai. Phase 2 has a logical-analysis prototype but is incomplete; the product UI currently exposes Phase 1 aggregates. See [current status](docs/PROJECT_STATUS.md), [roadmap](docs/ROADMAP.md), [acceptance evidence](docs/PHASE1_ACCEPTANCE.md) and [document index](docs/STATUS_INDEX.md).

## Build and test

Use a Mac with full Xcode selected as the developer toolchain and Swift 6.2 or newer (the code uses `isolated deinit`). Run from a clone:

```sh
Scripts/verify-local.sh
```

The script runs, in order:

1. `swift test` for Core, Capture, Store and Integration, then the revised harness's offline CLI regressions (no tap or posted events).
2. `swift build -c release` for SwiftPM targets.
3. An unsigned universal (`arm64 x86_64`) Release App build in a fresh directory.
4. A native-architecture Debug `build-for-testing`.
5. Hostless `xcrun xctest`, supplying `T23_RELEASE_APP` as the absolute path to that exact newly built universal Release App.

Each invocation retains logs and Xcode products under `.build/verification/run.*`; App test screenshots/artifacts go into that invocation’s `qa/` directory via `KEYRECORD_QA_OUTPUT_DIR`. It stops on failure, so later steps may not have run. Do not run concurrent verification against the shared SwiftPM build directory. App XCTest is separate from `swift test`; AppKit/accessibility checks need a suitable logged-in graphical session. A host limitation, failed assertion or skip is not a pass.

For a headless runner:

```sh
Scripts/verify-local.sh --build-only
```

This still runs SwiftPM tests and both App builds, but deliberately skips App XCTest. The ordinary [macOS CI workflow](.github/workflows/macos.yml) uses this mode. The workflow explicitly selects `/Applications/Xcode_26.3.app/Contents/Developer`, listed in the [official macOS 15 runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-Readme.md); [Swift 6.2.4 ships in Xcode 26.3](https://forums.swift.org/t/announcing-swift-6-2-4/85050). The local review/repair host uses Xcode 27.0 (27A266a), Apple Swift 6.4; CI passed at `b46316bbb` with Xcode 26.3. Later checks are revision-specific: consult the PR checks for the current commit; older CI or local results do not establish current remote compatibility. A green CI run proves only those tests and unsigned compilation. It does not launch capture, exercise WindowServer/VoiceOver, prove effective Keychain access, signing/notarization or native Apple Silicon product performance, or authorize host operations. The script's universal compilation is a development check, not an Intel requirement for the current MVP.

## Scope and host validation

For a provisioned Apple Silicon Debug trial, use
`bash Scripts/build-isolated-debug-trial.sh --help`. This builds a separately
identified, isolation-required App without installing or launching it. The
[historical September 29 checkpoint](docs/MVP_CLOSEOUT_20260929.md) records the tested candidate,
offline results, and the resolved local provisioning issue; a build or signature
check alone does not establish effective Keychain access.

The [Phase 1 acceptance record](docs/PHASE1_ACCEPTANCE.md) separates completed MVP evidence
from historical gaps and later requirements. No additional Phase 1 owner round is scheduled.

The portable implementation specification is [PHASE1_CONTRACT.md](docs/PHASE1_CONTRACT.md), with [PRD](docs/PRD.md) and [technical architecture](docs/TECHNICAL_ARCHITECTURE.md). No local `.omo` plan is needed to understand the behavioral contract or run ordinary verification. Historical evidence and its existing qualification procedures remain separate from these developer checks.

Any newly justified host run must identify the exact build configuration, App, identity, permitted store/Keychain namespace, actions and approved duration. Coordinate readiness before launch; use normal termination with an exact-instance forced-stop fallback. Historical 30–60 second and multi-minute controllers are candidate-specific, not a universal timer or instructions to repeat completed checks. New privacy, signing, Keychain or capture effects need applicable authorization; a successful build supplies none. Do not reset TCC, operate daily data or infer permission for a live run from build approval.

No runtime result is claimed by these instructions. Harness results cannot substitute for the real product pipeline. Lock or crash can lose all statistics since the last completed durable save; the one-second flush cadence is a scheduling target, not a bounded-loss guarantee. Production recommendation integration, mapping, FR-P6 full password backup and public release remain later work. The logical-analysis prototype does not qualify these features.

## Repository layout

- `Sources/`, `Tests/`: SwiftPM libraries and tests.
- `App/`, `KeyRecord.xcodeproj`: native product and App XCTest.
- `docs/`: product specification, architecture and status.
- `Scripts/`: development checks and existing qualification workflows.
- `Spikes/`, `evidence/phase0/`: historical experiments and evidence; preserve their original meaning and contents.
