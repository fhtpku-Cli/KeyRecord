# 路线图与当前交付状态

状态日期：2026-10-12，Asia/Shanghai。增量 A 的主体已由 [PR #19](https://github.com/fhtpku-Cli/KeyRecord/pull/19) 合并为
`adae0c4e429ff2c955b978f67a0afd069ce7708c`，[主干 CI 通过](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38246915859)。
本次工程收尾包括两项偏好交互修复及状态同步，不增加新门禁或实机验收轮次。

## Phase status

| Phase | Current state | Remaining scope / evidence boundary |
|---|---|---|
| Phase 0: feasibility | Capture prerequisites progressed beyond the old G0 OPEN writeback; historical artifacts remain unchanged | Karabiner version/reload/disable latency, VIA protocol/dialect/importer, Vial importer/live capture and backup KDF/Intel evidence retain their own limits. Phase 0 is not globally all-green. |
| Phase 1: collection, privacy, encrypted storage | **Approved Apple Silicon MVP complete and merged** | Measured arm64 macOS 27.0 build 26A428 only; development-signed local trial. Existing candidate-specific short ARM and lifecycle evidence retained. Full original G1/v1, all OS/architectures and public release are not claimed. |
| Phase 2：确定性分析 | **增量 A 工程收尾完成；完整 FR-R/FR-E 与 G2 未完成** | 概览、正向预览 Top 5、全部候选、忽略/恢复已接入，合成界面走查完成。真实输入及重开检查并入下次实际试用；物理评分、后端约束和手动候选属于 B。 |
| Phase 3: Karabiner stable path | **Not qualified as a usable product backend** | Transactions, conflict handling, configuration application/readback, rollback, backup retention, emergency disable and real supported-version behavior. Existing spikes are not product delivery. |
| Phase 4: VIA/Vial Beta | **Not qualified** | Separate definition/protocol/dialect/importer/device evidence, safe export/readback, and the specified real-keyboard coverage. Synthetic round trips do not establish device compatibility. |
| Full v1 / public distribution | **Not qualified** | PRD §15 requirements, FR-P6 full password backup, Intel/full support matrix, public name/license decision, signing/notarization and backend requirements remain. |

Requirements remain in [PRD](PRD.md) and [architecture §15](TECHNICAL_ARCHITECTURE.md#15-分阶段交付与发布门禁).
Current Phase 1 evidence is in [acceptance](PHASE1_ACCEPTANCE.md), not the old T24
projection or the baseline-bound `milestone-allocation.json`.

## 已确认的 Phase 2 方向与后续工作

用户于 2026-10-01 确认[产品方案](phase2/PRODUCT_PLAN.md)的 D1–D5。A 的主体已合并，2026-10-12 合成预览走查已完成；本次修复连续偏好操作覆盖和候选页失败提示，复用已有检查，只补五项直接相关用例。合并后按“增量 A 工程收尾完成”记录，不宣称完整实机验收或 G2 完成。

1. 本次修复通过正常提交、CI 与合并流程交付，不另跑全量本机测试。已有结果及限制见[验证记录](phase2/VALIDATION.md)。
2. 将 A 的真实输入、保存重开和产品链路偏好检查集中到下一次实际试用。真实按键下的 Top 5 尚无证据，不要求用户等两天或重复输入来补标签；合成跨日规则测试保留其独立范围。
3. B 已在隔离分支开始：[样例与方案](phase2/B_FOUNDATIONS.md)确定保留逻辑排名、物理次数/跨度独立展示。特殊键池、手动草稿/风险确认、能力/检查状态及物理解析/回退已进入首批实现；2026-10-13 第二批接入只读 VIA 文件选择、配对及会话内参考。下一步由用户准备配置副本/对应定义，实际操作系统选择器并核对真实配置边界；完整部署与变换链证据仍缺失，真实验证按用户要求稍后进行。完整需求映射沿用产品方案，不重开 D1–D5，也不将合成证据当真实收益。
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
