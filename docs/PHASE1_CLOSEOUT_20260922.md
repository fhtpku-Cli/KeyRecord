# Phase 1 offline acceptance closeout — 2026-09-22

Branch: `codex/phase1-acceptance-closeout`, based on `31b65c523db3ec40c06f0877395da52b7c026935` in a separate worktree. Product Sources/App/Package.swift are unchanged. This report measures the Phase 1 worktree, not the parallel Phase 2 branch. Remaining acceptance: [matrix](PHASE1_ACCEPTANCE.md).

## Repairs

- The compressed performance probe previously discarded typing-window physical-footprint samples and reported only idle memory. A deterministic red test observed a 120 MB typing peak incorrectly reported as 20 MB (mean 15 MB instead of 40 MB). The revised probe includes both windows and rejects missing/invalid samples. Focused measurement/receipt tests: 11 passed. This fixes measurement completeness, not product performance.
- The old capture harness ignored unknown arguments, so isolated execution of its extracted parser showed `--help` selecting physical/45 seconds and invalid mode/duration selecting typo/45 seconds. Its decoder also forced every event to ordinaryObserved despite marking its posted events. The revised CLI strictly validates arguments, offers help and a pure-memory offline mode, and returns BLOCKED for both live modes before any host access. The unsafe live implementation is retired because its one-time privacy sample and assumed unlocked state cannot continuously protect the user's session. Its historical source remains in Git; earlier live evidence is not rewritten.
- Receipt write failures now fail the command instead of silently losing the requested output. Revised SwiftPM-built CLI: 19 cases passed, including invalid arguments, blocked live modes and output failure/preservation cases. Offline Core source/aggregate fixture: 6 checks passed; product-marked events produce no aggregate. This is not an event-tap or full product-pipeline test.
- Current status now routes to the remaining acceptance matrix. The milestone/checkpoint retain their old results but explicitly identify their historical versions. Live notes distinguish bounded older observations from current qualification and correct the stale universal-build limitation.

## Verification performed

Environment: native arm64 Apple M3, Mac15,12, 16 GiB RAM, macOS 27.0 (26A428), Xcode 27.0 (27A266a), Apple Swift 6.4. Raw artifacts in this worktree: `.build/phase1-closeout/` and `.build/verification/run.jqMzpL/`.

| Check | Outcome and scope | Local evidence |
|---|---|---|
| Initial package regression | 480 passed: Core 219, Capture 65, Store 157, Integration 39; built before the new probe tests | `build-only.log` |
| Final package regression | 482 passed: Core 219, Capture 65, Store 157, Integration 41; zero failures after harness/probe changes | `final-package.log` |
| SwiftPM Release | Final changed targets compiled successfully | `final-swift-release.log` |
| App Release | Unsigned universal arm64 + x86_64 BUILD SUCCEEDED; product source unchanged by this work | `build-only.log`, `run.jqMzpL/release/` |
| App Debug test build | Native arm64 TEST BUILD SUCCEEDED | `build-only.log`, `run.jqMzpL/debug/` |
| Safe App test subset | 26 passed, zero failures: ProductReduction 9, LocalKeychainQueries 6, ProductReleaseBoundary 11 | `app-headless.log` |
| Release boundary | Both binary slices and bundle resources clean; one executable, no helpers; project restrictions pass | `release-boundary.log` |
| Static network capability scan | PASS, matches=0, liveReceipt=false | `release-network.json` |
| Host wrappers | capture/network/performance return exit 2 BLOCKED; missing arguments exit 1. No controller, tap, packet or sampling operation | `host-wrappers.json` |
| Harness CLI / offline fixture | 19 CLI cases, 6 fixture checks passed; no tap or posted events | `harness-swiftpm.log`, `harness-offline.json` |
| Probe regression | Red: expected typing peak omitted. Green: 11 focused tests passed, including short isolated measurement | `memory-red.log`, `memory-green.log` |

The App subset constructs Keychain dictionaries without calling SecItem, uses injected reducer state and scans copies of unsigned build artifacts without launching the App. Full App XCTest, UI screenshots, VoiceOver, live permissions, real statistics/Keychain, packet capture, lock/sleep/unlock, user switching and signed launch were **not** run. The initial full verify command was stopped during compilation and replaced with `--build-only` before App tests could execute. The selected safe tests were then run explicitly.

## Performance interpretation

Focused revised probe result: typing CPU median approximately 0.795%, idle median 0.277%, mean physical footprint 6.97 MB and sampled peak 7.14 MB. CPU uses one logical core. Budget result: **FAIL** (idle threshold <0.1%); full qualification: **BLOCKED**. These are 0.2-second warmups, one-second windows, two repeats, inside XCTest, including fixture/sampler overhead. Concurrent independent development builds may also affect scheduling. Do not compare these values as a product optimization or infer a product regression from them.

The final full-suite probe separately reported typing 1.028%, idle 0.259%, mean 24.59 MB and sampled peak 24.79 MB, also **FAIL/BLOCKED**. Different process history and concurrent load make the two short observations unsuitable as a stable product benchmark. Both raw receipts are retained; no failing measurement is hidden by the 482 passing test assertions.

Formal §12.4 acceptance still needs a qualified product workload/controller, 60-second warmup, 600-second typing/idle windows, three repeats and native ARM **and Intel** reference hardware. It must measure actual product behavior with isolated permitted data. Extending this XCTest timer alone would not provide that evidence. See the matrix for exact protocol and interruption handling.

## Limits and owner follow-up

G1 remains incomplete. Release still uses `BlockedLiveKeychain` / `UnqualifiedCapture`; no restriction was relaxed. No new hash, frozen contract, baseline or gate was added. Existing receipt format/identity checks remain intact.

The next owner-assisted step is a specifically approved bounded current-candidate count/pause/normal quit/restart trial, followed by separate privacy/session trials after their observation mechanism and operation scope are ready. Continuous closed-interval evidence, permission changes, user switching, real test-Keychain lifecycle, packet capture, Intel performance, signing and distribution remain outstanding. The matrix specifies the smallest practical sequence; unattended work cannot substitute for these observations.
