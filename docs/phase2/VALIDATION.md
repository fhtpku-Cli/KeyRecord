# Phase 2 validation

2026-10-13 合并与交付准备：PR #21 已合并为 `2c29f18e6`，最终 PR 的 push/pull_request CI 均通过。合并源码的开发签名 arm64 隔离包已构建并通过既有无启动检查；本轮没有运行实际试用。签名材料、首次手工 profile 构建失败、本地自动选择构建成功及后续短流程见 [试用准备记录](TRIAL_PREPARATION_20261013.md)。下文保留工程阶段的精确范围和历史结果。

## 增量 B 工程收尾与自行审查 — 2026-10-13

用户授权自主制定并完成工程收尾、自行 review，真实 VIA/设备验证继续延期。主 agent 在同一隔离分支审查新增模型、偏好事务、产品接线、只读解析、文件句柄和隐私失效路径，核对实际日志与双语原生截图；没有新增 hash、冻结 contract、baseline 或 gate，也没有扩大到真实采集、设备、网络或发行验证。

审查发现并修复两项问题：

1. **旧 Spikes 测试目标漏依赖。** 基点 `Spikes/Package.swift` 的 `Phase0ProbeTests` 只依赖 `Phase0Probe`，但三份测试直接导入并使用 `EvidenceValidator`。补齐直接依赖后，原先被链接阻断的 ViaDefinition 7 项和 ViaLayout 8 项合计 **15/15 实跑通过**；没有修改断言或历史证据。其他测试目标虽被编译，但未执行其用例。编译仍有旧 `SP1ValidatorV2Tests.swift` 未使用返回值警告，不属于本批源码。
2. **键池排队操作跨锁定重开。** 新反例让首个保存挂起、第二个选择排队，再锁定与重新打开；旧代码实际多保存一次，把旧 F2 带入新会话。修复在排队时获取已有 `KeyAvailabilityGate` generation 和当前周期，执行、发布及失败提示前核对，旧选择/迟到结果不再生效。没有添加新的门禁机制。新增反例先失败，修复后连同受影响的保存/撤回/失败、连续操作、隐私关闭和双语原生 toggle，**5/5 通过**。一次中间编译缺少局部函数的 `@MainActor` 声明，已补齐；最终未签名 arm64 构建成功。

本次执行的 20 项检查是原先受阻或受修复影响的范围；先前纯模型、导入和界面通过结果继续保留，未重跑全套。主 agent 执行原生 AX 勾选/撤回用例并查看最终中文键池截图，另检查英文 VIA 参考截图；此前中文 VIA、物理成本和风险确认截图的审阅记录见下文。自行审查结论：上述具体缺陷已解决，可整理为工程草稿 PR；完整 B、真实后端冲突检查、当前部署/变换链与实机验收仍未完成。

精确复跑范围：

```sh
# 在 Spikes 中执行；这与首次受阻命令范围相同
swift test --disable-sandbox --filter 'ViaDefinitionTests|ViaLayoutTests/(testExactSyntheticFixtureParsesWithoutBeingClassifiedAsSourcedOrLive|testSelectedSlotPatchPreservesEveryOtherByteAndOpaqueSubtree|testIdentityShapeMacroProtocolKeycodeAndMutationMismatchesRejectBeforeOutput|testMalformedTruncatedDuplicateAndInvalidContractReject|testInputByteBoundaryAcceptsExactAndRejectsPlusOne|testDepthBoundaryAcceptsExactAndRejectsPlusOne|testCollectionBoundaryAcceptsExactAndRejectsPlusOne|testScalarBoundaryAcceptsExactAndRejectsPlusOne)'

# 在根目录构建，无签名、无产品采集
xcodebuild -project KeyRecord.xcodeproj -scheme KeyRecordApp -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath /private/tmp/keyrecord-b-keypool-build ARCHS=arm64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO build-for-testing

KEYRECORD_QA_OUTPUT_DIR=/private/tmp/keyrecord-b-review-qa xcrun xctest -XCTest 'KeyRecordAppTests.AnalysisFlowTests/testFunctionKeySelectionPersistsWithdrawsAndReportsSaveFailure,KeyRecordAppTests.AnalysisFlowTests/testOverlappingFunctionKeyChangesUseTheLastSavedSet,KeyRecordAppTests.AnalysisFlowTests/testPrivacyClosureClearsFunctionKeysAndRejectsNewSelections,KeyRecordAppTests.AnalysisFlowTests/testQueuedFunctionKeyChangeCannotCrossLockAndReopen,KeyRecordAppTests.AnalysisFlowTests/testFunctionKeySettingsExposeNoticeAndNativeToggleInBothLocales' /private/tmp/keyrecord-b-keypool-build/Build/Products/Debug/KeyRecordAppTests.xctest
```

实际日志保留于 `/private/tmp/keyrecord-b-via-shared-compat-final.log`（15 项）、`/private/tmp/keyrecord-b-review-regression-test.log`（反例初次失败）、`/private/tmp/keyrecord-b-review-final-build.log`（中间编译失败）、`/private/tmp/keyrecord-b-review-final-build2.log`（最终构建）、`/private/tmp/keyrecord-b-review-final-tests.log`（5 项通过）。最终截图为 `/private/tmp/keyrecord-b-review-qa/key-pool-{en,zh-Hans}.png`。所有文件读取均为受控夹具；真实文件选择器授权与实机设备仍延期。

### 既有 CI 检查发现的遗漏与收尾

草稿 [PR #21](https://github.com/fhtpku-Cli/KeyRecord/pull/21) 的首轮 push/PR CI 在四项既有测试中失败：生命周期文件 253 行超过已有 `<250` 限制；新本地库及 directed dependencies 未登记在产品模块/import 白名单；私有 `VIAJSONValue: Decodable` 未登记在隐私类型审计。两次运行均为同一组问题，发生在包测试阶段，尚未进入后续 App 构建；首次记录不能称为 CI 通过。

修复将三个偏好公开命令移到 `LifecyclePreferenceCommands.swift`，共用事务方法保持 acquire/release、敏感可见检查、现有存储和并发字段合并；ports 和事务对象仍私有。现有产品边界检查按实际图显式增加零依赖、只导入 Foundation 的 `KeyRecordConfigurationRead`，分析模块只增加对它的有向依赖，外部依赖和 test-only tooling 隔离断言均保留。隐私审计仅登记私有输入解码类型，未添加 Encodable、持久化或可公开读取的原始配置。

只复验受影响的 12 项：四项失败边界/注册用例，加键池 2 项、布局 3 项和忽略 3 项，**12/12 通过**。命令为 `swift test --disable-sandbox --filter 'KeyboardPoolPreferenceTests|LayoutPreferenceTests|LifecycleBoundaryTests/testLifecycleFilesStayUnder250LinesAndImportOnlyFoundation|ProductBoundaryTests/(testManifestDeclaresOnlyLocalLibrariesWithDirectedDependencies|testAllProductImportsRespectSystemFrameworkAllowlist)|PrivacySerializationTests/testAllowlistWhenEnumeratingProductTypesRequiresExplicitRegistration'`（9 项）及 `swift test --disable-sandbox --filter IgnoredRecommendationPreferenceTests`（3 项）。日志为 `/private/tmp/keyrecord-b-ci-boundary-final-tests.log` 与 `/private/tmp/keyrecord-b-ci-ignore-final-tests.log`，CI 初次失败副本为 `/private/tmp/keyrecord-b-ci-failure.log`、`/private/tmp/keyrecord-b-ci-pr-failure.log`。完整远端检查状态以 PR 当前提交的 checks 为准；本地定向通过不替代远端构建，也不证明实机通过。

## 增量 B 第二批只读 VIA 参考 — 2026-10-13

同一隔离分支成批加入文件读取、纯解析、会话失效和产品参考展示后，集中执行直接相关验证。**新解析 8/8、App 导入 6/6 与更新后的双语目录检查 1/1 通过，未签名 arm64 `build-for-testing` 成功。** 此前首批 22 项结果保留，未重跑；本批未跑全量、签名、Release、性能或网络观察。

| 范围 | 已观察结果 | 证据边界 |
|---|---|---|
| `VIAReferenceParserTests` 8 项 | V2/V3 ID、矩阵索引与几何、所有层尺寸、未知动作和宏不升级证据、复杂布局降级、非法位置拒绝、重复键/超限保护、schema 边界均通过 | 临时/内置合成 JSON，未证明具体设备兼容 |
| `VIAImportFlowTests` 5 项文件/生命周期用例 | 实际临时文件双顺序配对；错误配对/JSON 撤回旧参考；原子替换撤回；隐私关闭拒绝迟到读和旧选择回调；目录/符号链接/FIFO/超限拒绝均通过 | 模拟采集端口、受控偏好夹具，未读日常配置或真实 Keychain |
| `VIAImportFlowTests` 1 项原生界面用例 | 双语 640×580 Form 完整展示参考及限制，AX 原生清除使参考消失 | 两张截图由子 agent 查看，主 agent 另查看中文；未操作系统文件选择面板 |
| `ScreenMatrixTests/testHappyLocalizationAudit` | 更新后的双语引用与目录检查通过 | 本地化一致性，不替代实机走查 |
| 既有 Spikes 15 项兼容用例 | 初次测试包链接失败，0 项执行；工程收尾补齐直接依赖后 **15/15 通过** | 精确原因、修复及最终日志见本文顶部，初次失败记录保留 |

共享重复键扫描器仅提取到产品可用模块，独立只读 diff 确认算法和四项限额相同，旧入口名称以 typealias 保留。ViaDefinition/ViaLayout 各用原 scanner，仅共享限额；Vial 没有本次提取接口的消费者。没有修改历史证据绑定或追加门禁。子 agent 只读审阅文件句柄/授权范围释放与失效路径，未发现具体缺陷；真实 security-scoped 文件选择授权的动态释放尚未测量。

本地证据：`/private/tmp/keyrecord-b-via-parser-tests.log`、`/private/tmp/keyrecord-b-via-app-build.log`、`/private/tmp/keyrecord-b-via-app-tests.log`；旧兼容阻断日志 `/private/tmp/keyrecord-b-via-shared-compat-tests.log`。解析与 App 精确命令、边界统一记录于 `/private/tmp/keyrecord-b-keypool-qa/phase2-b-via-parser-manual-qa.md`；截图为同目录的 `via-reference-{en,zh-Hans}.png`。临时证据可能过期，本段保留实际结果和限制。

文件副本只作为第 0 层静态参考，固件未证明已部署，设备、软件和系统链仍未知；候选排名和成本比较保持逻辑口径。用户已延期真实验证：后续准备一组指定 VIA 副本和定义后，实际操作系统选择器并核对参考限制，再同轮补 A 的真实输入/保存重开。完整 B、FR-R/FR-E、G2 与发行均未完成。

## 增量 B 首批离线模型与产品组件 — 2026-10-12 至 2026-10-13

工作目录为隔离 `network-acceptance-closeout/KeyRecord`，分支 `codex/phase2-b-foundations`，基于 `e6a4cf5e`。本轮成批实现特殊键池、手动候选/二次确认、能力与检查状态、规范物理模型和界面说明后集中验证。**22 项不同的直接相关用例最终均有通过结果，最终源码未签名 arm64 `build-for-testing` 成功。** 未跑本机全量套件、Release、性能、网络或 Phase 1 重验。

| 范围 | 用例数 | 证明的行为 | 结果 |
|---|---|---|---|
| `KeyboardPoolPreferenceTests` | 2 | 新键池保存/撤回/重载、其他偏好保留、失败保持旧值、隐藏状态拒绝 | PASS，内存偏好夹具 |
| `AnalysisTests/testPoolWithdrawalRecalculatesWithoutOfferingPrintableKeys` | 1 | 撤回后预览重算，不改统计/资格，不自动提供裸可打印键 | PASS，合成日聚合 |
| 新 App 键池逻辑用例 | 3 | 选择/撤回/失败提示、挂起保存时连续选择不覆盖、隐私关闭清空且拒绝新增选择 | PASS，临时文件偏好与模拟采集端口 |
| `CandidateConstraintTests` | 6 | 五类状态、部分检查不冒充无冲突、输入变化失效、作用域/键码/Fn双端能力、持续类排除、裸/Shift可打印键确认与取消、非法码/未知修饰键清除旧接受状态 | PASS，纯模型 |
| `PhysicalAnalysisTests` | 6 | 少按但跨度更大、重复按下、任一侧失败整对回退、不完整逆向覆盖/歧义拒绝、缺失/外部改变/多设备/作用域/坐标回退、链顺序/命名空间校验、重复/非有限几何拒绝 | PASS，明确合成证据 |
| 新原生 App 界面用例 | 3 | 双语 640×480 功能键原生勾选/撤回、风险取消/确认、640×260 物理跨度增加提示与逻辑回退 | PASS，AppKit 测试窗口、自身 AX 动作与截图 |
| `ScreenMatrixTests/testHappyLocalizationAudit` | 1 | 更新后的双语目录、引用和允许相同文本一致 | PASS |

独立子 agent 执行测试并审阅、查看六张截图；主 agent 另查看三张中文截图确认内容。自动构建/纯模型、临时偏好夹具、原生测试窗口和真实产品链路分别记录。**这些结果不证明真实 Keychain 加密偏好重开、采集中真实输入、当前 VIA 部署或真实物理收益。** 产品保存接线复用已有加密通路，夹具保存不是对真实加密 Keychain 的新验收。

### 失败修复与有限复验

首次 B1 界面用例定位到 SwiftUI `DisclosureGroup` 容器，`KRAXPress` 返回 false；改定位到实际 `AXDisclosureTriangle` 后，动作仍被拒绝。其他七项已通过结果保留，未重跑。本轮将功能键设置改为直接可见的原生 checkbox 网格，集中构建 B2/B3 后仅重跑失败界面项，并补两项新增界面与已变化的本地化检查；四项通过，六张双语截图生成。原始失败日志保留，没有删除/跳过断言来宣称通过。

子 agent 审阅发现能力约束最初只覆盖触发端；修复后同时检查原组合输出端的键码和 Fn。补“即使提供无冲突检查也不能绕过源输出能力”的反例，更新三个能力夹具，只复验四项受影响约束用例，均通过。最后增量构建对应最终源码，不重跑未受影响界面或物理模型。

### 本地证据与复跑入口

- `swift test --disable-sandbox --filter 'KeyboardPoolPreferenceTests|AnalysisTests/testPoolWithdrawalRecalculatesWithoutOfferingPrintableKeys'`：`/private/tmp/keyrecord-b-keypool-swift-tests.log`。
- `swift test --disable-sandbox --filter 'CandidateConstraintTests|PhysicalAnalysisTests'`：`/private/tmp/keyrecord-b-candidates-swift-tests.log`；受影响四项最终复验：`/private/tmp/keyrecord-b-constraints-final-tests.log`。
- 未签名 arm64 `build-for-testing` 最终日志：`/private/tmp/keyrecord-b-final-build.log`，产物 `/private/tmp/keyrecord-b-keypool-build/Build/Products/Debug/KeyRecordAppTests.xctest`。精确构建及 `xcrun xctest -XCTest` 筛选命令记录在 `/private/tmp/keyrecord-b-keypool-qa/phase2-b-candidates-manual-qa.md`。
- 初次 App 逻辑/界面结果：`/private/tmp/keyrecord-b-keypool-xctest.log`；单项第二次失败：`/private/tmp/keyrecord-b-keypool-ui-final-test.log`；集中界面修复与新增验证：`/private/tmp/keyrecord-b-candidates-ui-tests.log`。
- 截图目录 `/private/tmp/keyrecord-b-keypool-qa/`：`key-pool-{en,zh-Hans}.png`、`manual-risk-{en,zh-Hans}.png`、`physical-cost-{en,zh-Hans}.png`。临时日志/截图可能过期；本段保留已观察结果及限制。
- `python3 Scripts/phase2-cost-examples.py`：六个成本计算、九种回退和任意权重导致排序翻转检查通过；该脚本是合成设计样例，不是 VIA 解析器。

第一次命令因沙箱缓存与隔离工作树写权限失败发生在测试前，经已有授权的 auto-review 后以相同范围执行；不是产品测试失败或跳过。整个过程未启动真实产品采集、读日常配置、访问真实 Keychain 或操作设备。

### 尚未验证与下一入口

首批结束时尚未接入文件选择/导入，第二批实现与结果见本文顶部。用户已确认 VIA 配置副本/布局定义方向，但明确要求“稍晚些再验证吧”，当前仍无用户指定真实材料和完整物理证据提供器，运行产品继续显示未连接和逻辑回退。准备就绪的一次实际试用可关联验证 B 与 A 的真实输入/保存重开；不重新打开已完成 Phase 1 或网络观察。当前不能标记完整 B、FR-R/FR-E、G2 或发行通过。

## 忽略操作与失败提示修复：验证计划（2026-10-12）

本次仅修改忽略、恢复、撤销的异步操作顺序，以及“全部候选”页的偏好保存失败提示。两项修复完成后集中验证一次，复用已有无关验证结果。

只构建一次未签名 App 与测试目标，并执行 `AnalysisFlowTests` 中以下五项：

| 用例 | 本次需要证明的行为 |
|---|---|
| `testOverlappingIgnoresKeepBothSelectionsAndUndoOnlyTheLast` | 首次保存挂起时连续忽略两项，最终保留两项；撤销只撤回最后一项，界面与保存内容一致 |
| `testQueuedIgnoreUsesSavedStateAfterEarlierFailure` | 前次保存失败不阻断后续操作，也不把失败项带入下一次保存 |
| `testUndoWaitsForOverlappingRestore` | 恢复尚未保存时点击撤销，按操作顺序执行并恢复正确集合 |
| `testIgnoreFailureRollsBackAndRestoreSurvivesMissingObservation` | 复用现有的失败回滚、撤销及缺失观察记录回归 |
| `testCandidatesPageDisplaysPreferenceSaveFailure` | 合成候选页包含可被辅助功能读取的本地化保存失败提示 |

使用临时偏好夹具和合成分析数据，不启动产品采集，不访问真实 Keychain 或日常统计库。此次不执行全量测试、签名、安装、跨日真实输入、锁屏/睡眠、网络观察、性能或全套界面验收。编译成功只证明代码可构建；界面测试若无法取得节点，应记录未验证，不追加整套人工走查。

执行结果：两项生产修复的未签名构建成功，四项操作逻辑测试首次集中运行通过。界面测试初次按子节点标识定位失败；诊断树确认文案存在，但 SwiftUI 将其标识替换为父级标识。补全测试窗口布局并改为检查准确本地化文案及非零尺寸后，仅重跑该项并通过。未重复执行四项已通过测试；五项定向用例最终均有通过结果。本次未运行全量测试，也不新增实机验收要求。

本地日志：`/private/tmp/keyrecord-ignore-fix-build.log`、`/private/tmp/keyrecord-ignore-fix-tests.log`（含首次界面失败）、`/private/tmp/keyrecord-ignore-fix-ui-final-build.log`、`/private/tmp/keyrecord-ignore-fix-ui-final-test.log`。独立子 agent 对生产修复及窄范围验证计划给出 APPROVE，报告为 `/private/tmp/keyrecord-ignore-fix-code-review.md`；该审查结论不冒充测试结果。

## Increment A automated checks — 2026-10-01

These checks cover the statistics and logical-preview increment on
`codex/phase2-product-plan`. They do not accept full Phase 2, G2, or a signed
host round. The ImageRenderer blank-image skip below is the same pre-existing
limitation, not a new visual pass.

- SwiftPM, `swift test --disable-sandbox` filtered to `AnalysisTests`,
  `IgnoredRecommendationPreferenceTests`, `LayoutPreferenceTests`, and
  `CycleResetTests/testResetKeepsIgnoredKeysLayoutAndUnrelatedPreferences`:
  16 analysis tests, 3 ignore-preference tests, 3 layout tests, and the cycle-reset
  retention test passed. The analysis run includes positive-preview Top 5,
  no-plan and Fn-unknown reasons, ignore, score ties, canonical ignore parsing,
  and a 420-row analysis that finished in 0.009 seconds. The full package suite
  was not rerun.
- Unsigned arm64 App XCTest, `CODE_SIGNING_ALLOWED=NO`: `AnalysisFlowTests`
  executed 11 tests with 1 skipped and 0 failures; `ProductSnapshotPublicationTests`
  executed 11 tests with 0 failures. Coverage includes privacy clearing, stale
  cycle rejection, ignore save/failure/undo, opening statistics without start or
  resume, and analysis failure leaving the aggregate readable.
- `ScreenMatrixTests/testHappyScreenMatrix` passed after layout choices used the
  existing focusable action control. Localization audit methods passed.
  `kern.osversion` is recorded as a non-UI literal.
- `testSyntheticDashboardRendersBothLocalesAndPrivacyStates` skipped because
  ImageRenderer still produced a blank image. That is not a rendering pass.
- No signed Release launch, no real capture, no VoiceOver session, and no owner
  walkthrough were run. Hostless accessibility initialization is not treated as
  interactive acceptance.
- A separate review of the uncommitted increment A diff found no privacy,
  capture-lifecycle, stale-analysis, or network issue. It is not a signed host review.

## Isolated trial, second segment — 2026-10-12

The owner finished the agreed second segment on the isolated Debug trial and then
quit. The trial bundle is `com.keyrecord.trial.mvp20260929`, namespace
`com.keyrecord.trial.mvp20260929.phase2a20261001`, store
`keyrecord-increment-a-trial-auto/runtime-phase2a/store`. The machine is Apple
Silicon macOS 27.0.1 build `26A434`. That build is not the measured Phase 1
acceptance platform, which remains arm64 macOS 27.0 build `26A428`. The binary
uses the local Apple Development identity. This is not a notarized or public
release, and it is not full Phase 2 or G2.

Before this launch the trial store was empty. At 17:11:54 it contained a manifest
and two encrypted objects, so first consent provisioned protected storage. The
process was gone after the owner reported the segment complete. The termination
summary written at 17:12:20 shows no live capture session, an open key gate, two
sessions, one successful durable flush, and no flush failure. Tap callbacks and
the aggregate delta are zero. Statistics publication ran 23 times with no
rejection; snapshot publication ran 13 times with no read failure. The last
published shortcut total and bare-key total are both zero. Sensitive content was
not visible in that final snapshot.

This establishes that consent on a fresh trial namespace can create the encrypted
store, that capture was no longer live at exit, and that the published statistics
stayed empty. It does not show typed shortcuts, Top 5, ignore or undo, a bilingual
or VoiceOver pass, or the on-screen pause label. The final summary does not
explain why the session count is two.

## Synthetic preview walkthrough — 2026-10-12

The owner finished the agreed synthetic-preview checklist and reported no
mismatch. The window title was “Synthetic analysis preview”. The process was an
unsigned Debug build launched with only `KEYRECORD_ANALYSIS_PREVIEW=1`; real
capture, the trial store, and the trial namespace were not set. The preview
keeps ignore, undo, restore, and layout choice in memory for that window. That
wiring is a local preview change and is not part of commit `3b66af5ba`.

The checklist covered Top 5 membership, the no-plan explanation in all
candidates, ignore/undo/restore, layout choice and skip, English and Chinese,
a narrowed window, keyboard focus, VoiceOver reading of a candidate status and
count, and the empty and hidden fixtures. No apply, export, or remap control
was part of the check. The owner did not write a separate note for each control,
and this session did not capture screenshots or an accessibility tree. The
ImageRenderer blank-image skip remains unresolved. This is the increment A
interface check, not typed-shortcut evidence, increment B, or full Phase 2/G2.

## Historical prototype validation

The sections below record the earlier read-only Debug prototype. They are not Phase 1 acceptance, Release qualification, or acceptance of increment A.
Status reconciliation (2026-10-01): [Phase 1 is complete](../PHASE1_ACCEPTANCE.md),
but its native walkthrough does not qualify this separate dashboard or full G2.
The instructions below describe prototype reproduction and remaining coverage,
not authorization to start another host round. See [implementation scope](IMPLEMENTATION.md)
and the [current roadmap](../ROADMAP.md).

## Synthetic-only reproduction

Build `KeyRecordApp` Debug with Xcode. Launch its executable with a clean environment and `KEYRECORD_ANALYSIS_PREVIEW=1`. This DEBUG-only entry returns before ProductComposition, real capture, preferences, store or keychain initialization. Do not set `KEYRECORD_LOCAL_CAPTURE`.

The preview contains only fixed aggregate fixtures. Use the language picker and populated/empty/hidden picker. Choose ANSI/ISO/Alice/Split or skip; expand factors and sided provenance; toggle all candidates; select global/top application. Changes in this isolated preview remain in memory. The production layout action separately uses existing encrypted preference transactions.

Run `swift test --disable-sandbox`, and build-for-testing the Xcode scheme; run hostless `AnalysisFlowTests` using `xcrun xctest -XCTest AnalysisFlowTests <test bundle>`. Set `KEYRECORD_QA_OUTPUT_DIR` to a disposable directory for six synthetic native-render images. These are in-process render tests, not proof of physical keyboard, VoiceOver or real session-lock behavior.

## User-return manual checklist

- Open only the synthetic preview; do not start real capture.
- Verify English and Chinese at 1000×700 and 640×480, light/dark appearance, and large text.
- Tab/Shift-Tab through layout buttons, candidate toggle, disclosure controls and scope radios; activate with Space/Return. Read key statuses and counts with VoiceOver.
- Confirm Top 5 versus all candidates, 8-use observation, Cmd-Tab exclusion, unknown application disabled scope, Fn-unknown no-trigger explanation, suspected-source factors.
- Pick a layout and confirm the question disappears; choose skip and confirm the same. Production persistence is covered by isolated preference tests, not real-keychain observation.
- Switch to hidden and confirm no statistics/candidates remain, then empty and confirm explicit empty messaging.

## Desktop automation limitation

Computer-use inspection failed with `Sky Computer Use native pipe closed before response`, and later exact-app-path retries returned `-10005 timeoutReached`. No assistant AX tree, screenshot or click was obtained. Owner-provided screenshots and explicit interaction feedback now supply the scoped manual evidence below. No wake, unlock, sleep prevention, TCC change, real input capture or external remap was attempted. A successful build or bitmap render does not establish interactive acceptance.

Both attempted offscreen capture methods also failed visual inspection: NSView caching produced mostly black images; SwiftUI ImageRenderer produced a blank white dashboard. The render test now checks for content and reports SKIPPED when absent. Image file creation/size alone is not counted as a rendering pass. Images remain local under /tmp and are not presented as UI evidence.

## Earlier automated checks observed (before UI follow-up)

- Pure Swift targeted suite: 28 tests passed (12 analysis, 3 layout, 7 lifecycle boundaries, 6 product/module boundaries). Log: `/tmp/keyrecord-phase2-targeted-final.log`.
- SwiftPM Release build passed: `/tmp/keyrecord-phase2-swift-release-final.log`.
- Unsigned Xcode universal Release build passed: `/tmp/keyrecord-phase2-release.log`; this is compilation only, not ARM/Intel execution or release qualification.
- Synthetic App integration: privacy clearing, layout success/failure, exact-side display merge, protected reduction read all passed. Offscreen render is unavailable and must be reported as skipped.
- Full sandbox Swift run encountered process/cache/file-access failures and an old module allowlist expectation; the module expectation was corrected and targeted structural checks passed. Performance probe reported `translatedHost` under sandbox. This does not diagnose actual translation or qualify performance.
- Automatic approval rejected an elevated full Swift suite because it includes capture/system-level tests. That action was not retried indirectly. Only explicitly isolated pure test classes were subsequently run with elevation.
- Full hostless App suite was stopped during existing `PrimitiveStateTests.testFailureStressMatrix`, with desktop unavailable. Its old module-list assertion was updated for the new target; the aborted suite is not a pass.


## Owner-assisted UI follow-up — 2026-09-22

The owner approved synthetic-only preview runs. Screenshots and chronological observations are retained locally in the main checkout under `.omo/repair-20260922/phase2-ui-validation/` (`RUN.md`, screenshots01–12). They contain fixed synthetic fixtures, not real captured statistics.

| Evidence | Observed result | Scope |
| --- | --- | --- |
| Screenshots01–02 | English populated view, Chinese factors and exact modifier details rendered | Before follow-up changes; sampled visible cards |
| Screenshots03–04 | ANSI changed layout factor0.50→0.75 and score21.47→32.20;44 uses/2days unchanged; Global selection visible | Synthetic in-memory interaction, not real preference persistence |
| Screenshots05–06 | 8-use observation, Cmd-Tab exclusion and unknown-application explanation | Before follow-up changes |
| Screenshots07–09 | Explicit empty state, hidden details, populated restoration and narrow-card wrapping | Before follow-up changes; no AX non-disclosure claim |
| Screenshots10–11 | Revised toolbar labels fully visible and no-trigger card says sample threshold met | Current follow-up build, supplied narrow viewport; vertical fallback not observed |
| Screenshot12 | Dark no-trigger card and expanded factors visually readable; long paragraphs wrap | Current follow-up build, one Chinese viewport; no quantitative contrast measurement |
| Owner keyboard report | Tab/Shift-Tab navigation and Space activation worked after enabling macOS Keyboard navigation | Before follow-up changes; initial apparent failure occurred with the system setting off |
| Owner VoiceOver report | Candidate names/counts read and factors disclosure activated using the instructed shortcut | Current follow-up build; owner explicitly distinguished this from merely enabling VoiceOver |

Follow-up implementation relabels eligibility as meeting the sample threshold, explains that this does not guarantee a simpler trigger, uses neutral empty-list copy, and adapts native preview pickers to available width. It does not change analysis scoring, collection, persistence or privacy logic.

Current ARM Debug build-for-testing passed, and four explicitly selected non-graphical `AnalysisFlowTests` passed with zero failures: privacy clearing/fresh publication, temporary-fixture layout persistence and save failure, protected-generation reduction, and exact-side display counts. Both locale catalogs passed `plutil -lint`, and `git diff --check` passed. Logs: `followup-build.log`, `followup-tests.log` in the local evidence directory. The first build command mixed app x86_64 compilation with arm64 package dependencies and failed; the local-preview retry set `ARCHS=arm64` explicitly without changing release settings. No fresh universal Release qualification is claimed.

Remaining qualification: the full locale × size × appearance matrix, large text, all keyboard controls and screen-reader order, hidden-state AX non-disclosure, and the preview's vertical fallback have not been verified. Earlier screenshot evidence must not be relabelled as fresh current-build evidence. The no-trigger factors row still describes zero saved keys as the first preview despite no generated trigger; this is a minor wording follow-up, not a positive savings claim. Basic owner-assisted checks do not constitute full accessibility, G2 or Release acceptance.


## Unknown modifier side repair — 2026-09-22

Joint PR5/PR6 review found that the default formatter omitted the unknown-side marker and the statistics grouping merged unknown sides with known sides, contrary to architecture §4.5. The repair reuses the existing localized marker and keeps unknown groups separate; confirmed left/right/both still merge. Stored identities/counts, ranking, capture and preference behavior are unchanged.

Two new regressions failed before the fix: the fixture produced2 groups rather than3 and unknown totals were combined with known sides; all four modifier families lacked their default unknown labels in both locales. After the fix, six selected non-graphical AnalysisFlow tests passed. The isolated combined PR5/PR6 build with the same source repair also passed15 selected App analysis/reduction tests. These bounded synthetic runs do not qualify a live host.

The owner explicitly approved launching the repaired combined Debug preview with only KEYRECORD_ANALYSIS_PREVIEW=1 in a clean environment. Fresh owner captures confirm the Chinese frequent-statistics Z row shows 命令（侧别未知） and20 uses, and the English candidate Z card shows Command (side unknown),20 raw uses across2 local days, separately marks Fn state unknown, and exposes no mapping action. These are two distinct visible regions, not the full bilingual surface matrix. The same-key known/unknown separation is proven by the regression fixture, not by a paired row in these screenshots. Evidence is retained locally under `.omo/repair-20260922/integration-review/` in the main checkout: `side-zh-statistics.png`, `side-en-candidate.png`, `side-red-tests.log`, `side-green-tests.log`, `integrated-fix-tests.log`. No assistant-driven AX interaction or fresh VoiceOver claim is made.

## Cursor pulse-publication follow-up (2026-09-22)

PR #6 review identified two composition defects: an analysis-only error escaped to the
pulse's protected shutdown handler, and a dead collecting session could republish
statistics after `sync()` had hidden them. Publication now checks lifecycle visibility
and capture liveness before reading either snapshot; paused sessions still retain their
statistics. Only `AnalysisError` is downgraded to an unavailable preview. Key-gate,
stale-generation, snapshot-read and other errors still propagate to the existing pulse
shutdown handler. The synchronous refresh uses the same analysis-error policy.

The production publication step was extracted without fixing its behavior first. Four
synthetic runtime tests then produced eight failed assertions in the two reported paths;
healthy publication and key-closure propagation already passed. After the repair, eight
publication tests plus six existing analysis-flow and nine reduction tests passed (23
total). Coverage includes real analysis validation failure on a synthetic misclassified
row, repeated dead-session ticks, healthy recovery, paused statistics, privacy closure,
and gate/read errors. Debug App and test-target compilation passed.

These are direct executions of the production publication function with real in-memory
lifecycle/reduction/analysis objects. They do not instantiate the full App composition,
run the one-second timer or OS capture, inspect the physical menu-bar badge, or qualify
real Keychain/privacy/Release behavior. No owner data or system setting was changed.

PR #7 follow-up: a dead refresh could reset the displayed login-item setting and
leave the UI blocked after the recovery coordinator had already refreshed its
cached liveness. Two regression tests reproduced five assertion failures.
Publication now mirrors current lifecycle state on every refresh, and the shared
blocked presentation operation clears content without changing login-item fields.
The recovery test no longer manually synchronizes the flow before asserting a
live refresh. All 24 selected synthetic tests passed, including nine publication
cases. This remains publication-level runtime evidence, not a live timer or OS
login-item registration test.
