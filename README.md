# KeyRecord

KeyRecord is an in-development native macOS menu-bar app for local, aggregate keyboard-use statistics. It aims to count shortcuts by application and bare keys without storing typed text or event sequences. The codebase uses Swift 6, macOS 14+, and Apple system frameworks.

**当前阶段（2026-10-13）：Phase 1 的 Apple Silicon MVP 已完成；Phase 2 增量 A 工程收尾与 B 基础能力已合并。** A 的统计概览、全部候选、正向逻辑预览及加密偏好接入已随 [PR #19](https://github.com/fhtpku-Cli/KeyRecord/pull/19) 合并，提交为 `adae0c4e429ff2c955b978f67a0afd069ce7708c`。此前 A 收尾修复连续忽略/恢复/撤销的覆盖问题，以及候选页保存失败提示，五项直接相关测试均有通过结果。已有合成界面走查继续有效。

增量 B 的工程基础与只读 VIA 参考已于 2026-10-13 随 [PR #21](https://github.com/fhtpku-Cli/KeyRecord/pull/21) 合并：特殊键池、手动候选/风险确认、后端检查状态与物理成本/回退模型，以及文件选择、配对和会话内参考均已接入。保留逻辑排名，次数与跨度独立说明；真实 VIA 配置及设备验证留稍后，静态副本仍不足以改变物理证据口径。[隔离试用包已准备，实际试用未执行](docs/phase2/TRIAL_PREPARATION_20261013.md)。见 [B 样例与方案](docs/phase2/B_FOUNDATIONS.md)、[实现状态](docs/phase2/IMPLEMENTATION.md)和[定向验证](docs/phase2/VALIDATION.md)。完整 B/G2 尚未完成。

当前代码在原生 arm64 macOS 27 及以后版本读取实时锁屏状态；锁定或未知时仍关闭保护，不因系统版本未列入历史实测记录就自动禁用。Phase 1 实测范围仍为 macOS 27.0 build `26A428`，A 的同意与空统计试验运行于 27.0.1 build `26A434`，两者不代表所有后续系统均已实测。A 的真实输入及重开检查留到下一次实际试用，本次不单独再开验收轮次，也不标为通过。完整 Phase 2/G2、增量 B 和公开发行尚未完成。见[当前状态](docs/PROJECT_STATUS.md)、[路线图](docs/ROADMAP.md)、[验证记录](docs/phase2/VALIDATION.md)和[文档索引](docs/STATUS_INDEX.md)。

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

构建说明不代表实机行为已经验证，夹具结果也不替代真实产品链路。锁屏或崩溃可能丢失上次成功持久化之后的统计，一秒保存节奏不是数据丢失上限保证。A 已接入统计与逻辑预览；物理评分、后端约束、映射应用、FR-P6 完整密码备份和公开发行仍是后续工作。

## Repository layout

- `Sources/`, `Tests/`: SwiftPM libraries and tests.
- `App/`, `KeyRecord.xcodeproj`: native product and App XCTest.
- `docs/`: product specification, architecture and status.
- `Scripts/`: development checks and existing qualification workflows.
- `Spikes/`, `evidence/phase0/`: historical experiments and evidence; preserve their original meaning and contents.
