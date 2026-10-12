# 路线图与当前交付状态

状态日期：2026-10-13，Asia/Shanghai。增量 A 的主体已由 [PR #19](https://github.com/fhtpku-Cli/KeyRecord/pull/19) 合并为
`adae0c4e429ff2c955b978f67a0afd069ce7708c`，[主干 CI 通过](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38246915859)。
B 的工程基础及只读 VIA 参考已由 [PR #21](https://github.com/fhtpku-Cli/KeyRecord/pull/21) 合并为 `2c29f18e6`。开发签名 arm64 隔离试用包和短流程已准备，实际试用未执行；见 [准备记录](phase2/TRIAL_PREPARATION_20261013.md)。不增加新门禁或实机验收轮次。

## Phase status

| Phase | Current state | Remaining scope / evidence boundary |
|---|---|---|
| Phase 0: feasibility | Capture prerequisites progressed beyond the old G0 OPEN writeback; historical artifacts remain unchanged | Karabiner version/reload/disable latency, VIA protocol/dialect/importer, Vial importer/live capture and backup KDF/Intel evidence retain their own limits. Phase 0 is not globally all-green. |
| Phase 1: collection, privacy, encrypted storage | **Approved Apple Silicon MVP complete and merged** | Measured arm64 macOS 27.0 build 26A428 only; development-signed local trial. Existing candidate-specific short ARM and lifecycle evidence retained. Full original G1/v1, all OS/architectures and public release are not claimed. |
| Phase 2：确定性分析 | **A/B 工程开发与离线自审完成；真实 G2 证据后置** | 能力过滤、范围明确的冲突检查、特殊键池、手动候选、物理链消费/回退与只读副本已接通。实际后端、完整真实部署/变换链、系统选择器授权和真实保存重开集中留后；产品不冒充已连接或真实物理收益。 |
| Phase 3: Karabiner stable path | **核心事务/原生流程增量完成；完整 Phase 3/G3 未完成** | 已实际离线执行草稿、保序 diff、重检、加密事务、读回/崩溃三分类、外部三选一、回滚、十份备份和停用。默认产品会话仍为副本预览/导出；部署目标/生命周期和完整卸载准备继续开发。真实版本、重载、效果及停用 p95 集中后置。[增量记录](phase3/CORE_ENGINEERING_20261013.md)。 |
| Phase 4: VIA/Vial Beta | **Not qualified** | Separate definition/protocol/dialect/importer/device evidence, safe export/readback, and the specified real-keyboard coverage. Synthetic round trips do not establish device compatibility. |
| Full v1 / public distribution | **Not qualified** | PRD §15 requirements, FR-P6 full password backup, Intel/full support matrix, public name/license decision, signing/notarization and backend requirements remain. |

Requirements remain in [PRD](PRD.md) and [architecture §15](TECHNICAL_ARCHITECTURE.md#15-分阶段交付与发布门禁).

2026-10-13 最新工程增量为 [Phase 3 核心事务与原生流程](phase3/CORE_ENGINEERING_20261013.md)，62 项不同的相关离线场景最终通过。默认产品尚无真实写入会话和生产支持矩阵。后续先补齐部署会话及卸载准备，再推进 Phase 4；不将本批临时配置/注入端口或旧 spike 当作真实后端合格证据。

2026-10-13 最新开发结论：**增量 B 工程开发与离线自审已完成**，后端能力过滤、观测/系统风险/规则重叠/映射环/保护入口检查及证据失效已接通产品；见 [完成记录](phase2/B_COMPLETION_20261013.md)。正式 G2 的真实证据仍后置，下一阶段的工程开发进入 Phase 3。下列早期试用安排仅保留历史范围，当前不要求执行那一轮试用。
Current Phase 1 evidence is in [acceptance](PHASE1_ACCEPTANCE.md), not the old T24
projection or the baseline-bound `milestone-allocation.json`.

## 已确认的 Phase 2 方向与后续工作

用户于 2026-10-01 确认[产品方案](phase2/PRODUCT_PLAN.md)的 D1–D5。A 的主体已合并，2026-10-12 合成预览走查已完成；本次修复连续偏好操作覆盖和候选页失败提示，复用已有检查，只补五项直接相关用例。合并后按“增量 A 工程收尾完成”记录，不宣称完整实机验收或 G2 完成。

1. 本次修复通过正常提交、CI 与合并流程交付，不另跑全量本机测试。已有结果及限制见[验证记录](phase2/VALIDATION.md)。
2. 将 A 的真实输入、保存重开和产品链路偏好检查集中到下一次实际试用。真实按键下的 Top 5 尚无证据，不要求用户等两天或重复输入来补标签；合成跨日规则测试保留其独立范围。
3. B 的工程基础与只读 VIA 参考已由 PR #21 合并：[样例与方案](phase2/B_FOUNDATIONS.md)确定保留逻辑排名、物理次数/跨度独立展示。开发签名隔离包和合成 JSON 已准备，可在用户方便时用一次短流程观察 A 的真实输入/保存重开及 B 的文件选择/参考展示。真实 VIA 副本、对应定义和完整部署/变换链证据仍缺失，真实设备验证按用户要求稍后进行。完整需求映射沿用产品方案，不重开 D1–D5，也不将合成证据当真实收益。
4. 系统升级采用向前兼容策略，运行时锁定或未知仍关闭保护。历史实测平台是证据范围，不是逐版本放行名单。下次需要安装时再核对当前签名材料；历史 profile 到期记录不代表当前证书状态。

Phase 3/4 application/export follows its original safety requirements. This
recommendation does not waive physical scoring, manual-trigger confirmation,
backup, compatibility or public-release requirements to declare an easier success.

## Meaning of completion and historical status

- A scoped MVP completion means the approved scope and cited observations, not
  every full-product gate or every historical runner has become PASS.
- Signed Release denotes the build configuration and development-signed candidate;
  it does not mean notarized/publicly distributed release.
- Automated package/unsigned build CI, real Keychain scenarios, user-supplied UI
  observations and performance measurements remain distinct evidence layers.
- Old BLOCKED/FAIL/SKIPPED records remain truthful for their inputs and dates.
  A consumed preparation file is not a request to relaunch. Local `/private/tmp`
  evidence paths may expire; the versioned reports retain their assertions and
  limits, but do not guarantee raw artifacts remain independently reproducible.
- See [the document index](STATUS_INDEX.md) for current guidance versus records.
