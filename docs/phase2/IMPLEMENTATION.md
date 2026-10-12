# Phase 2 统计与逻辑预览实现

## 增量 B 首批实现（2026-10-12，隔离分支）

本轮工作位于 `codex/phase2-b-foundations`，基于合并 A 收尾的 `e6a4cf5e`；尚未合并主干。方案及样例见 [B_FOUNDATIONS](B_FOUNDATIONS.md)。用户确认保留逻辑排名，物理次数与跨度分别说明；首批真实配置采用用户指定 VIA 副本及对应定义，真实验证稍后再做。

- 特殊键池 F1–F20 设置已通过现有 `Preferences.updating` 和可见偏好事务接通产品保存。`FlowModel` 排队保存完整选择操作，前次完成后才计算新集合；失败不改变旧值。产品 `syncRuntime` 用已保存偏好重算，撤回不影响统计和资格。默认池仍空，选择不代表键位可用或无冲突。
- `CandidateConstraints` 用显式后端能力、当前组合/作用域/布局/键池/规则与物理证据作为检查输入。未连接、不支持、未检查、冲突、检查通过分别表达；完整输入值变化使旧检查不可复用，未知或空证据不会变成通过。设置的后端选项只是本次会话意向，真实适配器仍未连接。
- 候选详情提供标准 macOS 键码和明确左右/双侧修饰键编辑。未分配码、宏文本、修饰键作为终止键、未知状态及持续类被拒绝。可能影响文字输入的裸键与 Shift/Fn 组合须明确二次确认；取消和编辑使草稿失效，确认不跳过后端/冲突检查。草稿仅存本次详情，不写映射或偏好字段。
- `PhysicalAnalysis` 只消费自包含规范几何、实际变换数据及明确状态/引用。需要显式完整固件→软件→系统链，覆盖相关逆向动作，恰好唯一且坐标可比；任一侧失败则原组合与候选整对按逻辑键数比较。重复按下计多次；跨分体相对坐标未知不比较跨度。物理次数/跨度独立输出，没有任意兑换权重，不改变 A 排名。
- 概览和候选说明已接入物理口径/回退解释；详情包含手动草稿和独立准备度。当前产品没有真实 `PhysicalEvidence` 提供器，运行时仍诚实显示逻辑回退。公开类型和合成 `verified` 输入不能作为真实固件已验证证明；可信配置来源、当前部署状态、设备与链完整性须由后续只读接入确定。

2026-10-13 第二批加入原生 JSON 文件选择、VIA 配置副本/布局定义只读解析及会话内参考接入。设置展示文件名、匹配结果和限制，候选详情展示第 0 层标准终止键的参考位置数量。按键盘 ID 与矩阵尺寸匹配；简单未旋转 KLE 几何转换为键距单位中心坐标。布局选项、旋转或复杂形状不猜几何；未知键码、层动作及宏不猜动作。解析后的固件状态仍为缺失，设备未知，软件和系统变换未观察，完整逆向覆盖为空；逻辑排名及物理整对回退保留。

`KeyRecordConfigurationRead` 提取既有重复键扫描及 8 MiB/深度 64/集合 100000/标量 1 MiB 限额，旧 Phase0Support 入口用 typealias 保留，产品不依赖 Spikes。文件以非阻塞、拒绝符号链接的只读句柄打开，确认普通文件后才读取；有界读取与发布前核对现有隐私 generation。文件监测从读取前开始，改写/替换使参考失效；清除、关闭敏感内容取消读取和监测，旧文件选择回调无法跨隐私会话发布。只保留规范化参考，不持久化路径、宏正文或原始配置，也不自动重读。

本轮仅读取临时合成文件，没有读取日常配置或连接设备。真实文件选择流程、当前部署及后端适配器仍待用户准备材料后验证。完成的模型与界面不代表完整 B、FR-R/FR-E、G2 或真实物理收益完成；验证结果和边界见 [VALIDATION](VALIDATION.md)。下方为增量 A 及历史原型记录，旧的“留待后续”描述保留其当时范围，以本节为本轮实现状态。

2026-10-13 工程收尾自行审查：补齐旧 `Phase0ProbeTests` 已实际使用的 `EvidenceValidator` 直接依赖，原先受阻的 15 项兼容用例通过。反例复现功能键排队选择在锁定重开后继续生效，现复用已有隐私 generation 和周期核对，执行及发布/失败提示均拒绝过期操作；受影响 5 项流程/原生界面用例通过，最终未签名 arm64 构建成功。未重跑未受影响结果，也没有新增门禁或改历史证据。

2026-10-12 工程收尾：A 主体已由 PR #19 合并，合成预览走查完成。本次将忽略、恢复、撤销的完整操作排队，等前次保存结束后再计算新集合，并在全部候选页显示保存失败提示；仅补直接相关测试。真实输入及重开、真实产品链路偏好检查留到下一次实际试用，不能将工程收尾称为完整实机验收或 G2 完成。

范围：当前周期每日聚合 → 确定性统计 → 可解释的逻辑建议预览。复用既有采集、受保护存储和隐私生命周期，不新增固件或外部配置写入。Phase 1 实测记录保持原候选范围，A 的产品接入不等于物理收益或后端应用已经验证。

Current integration: consented `ProductScreens` uses Overview / All candidates /
Settings. Overview reads the protected analysis snapshot, keeps Top 5 to eligible,
unignored, positive logical previews, and leaves no-plan items in All candidates.
Ignore, undo, and restore use the existing encrypted preference transaction.
Opening statistics does not start capture, and Pause is not turned into Resume.
The Debug synthetic preview still bypasses product composition. Full FR-R/FR-E
and G2 remain incomplete. See [roadmap](../ROADMAP.md).

The [Phase 2 product plan](PRODUCT_PLAN.md) records owner approval of D1–D5 on
2026-10-01. Increment A now implements P2-A1–A5 and the automated part of P2-A6.
The 2026-10-12 owner synthetic-preview check is recorded in [validation](VALIDATION.md).
Physical scoring, backend capability, manual candidates, and external apply/export
stay in later scope. Increment A is not full Phase 2 or G2.

Historical implementation sequence:
1. Completed: pure analysis module and synthetic rule-boundary tests.
2. Completed: protected snapshots, encrypted layout preferences and bilingual native dashboard implementation.
3. Automated builds and synthetic tests completed. Owner-assisted screenshots and keyboard/VoiceOver smoke checks cover the bounded scenarios in [validation](VALIDATION.md); desktop automation and full visual/accessibility qualification remain unavailable.
4. PR #6 merged as `9da1d24729e3a12883998c90522a77933e7a99b2`; PR #7 merged as `3b9345c30086e9e33c4510047e2692337f5b8643`. Joint review repaired unknown-side display/grouping; PR7 additionally isolates analysis failures and restores live presentation while preserving login-item fields. Earlier screenshots and synthetic tests retain their original candidate boundaries. Current-main bounded input/pause/restart observations are recorded, but complete real-use acceptance remains pending; see [the bounded collaboration record](../CURRENT_MAIN_ACCEPTANCE.md).

Design: preserve exact chord sides and unknown attribution in the domain, merge confirmed left/right/both modifier sides for display, keep unknown sides separately labelled, and retain expandable exact provenance. Ranking uses explicit active-day order, never elapsed wall time. The threshold uses raw cycle counts and distinct dates. All trigger choices are unverified logical previews; no mapping action is available. Missing physical evidence always means logical chord counts. Layout choice is a single existing preference, asked non-modally at the first qualifying dataset, with an explicit skip choice.

Authorization recorded for that prototype work is historical, not standing permission
to launch host rounds. Future work follows current task authorization.

## Rule choices and limits

`phase2-logical-v1` implements the architecture score: weighted frequency × maximum logical keys saved × source factor × layout factor. Ordinary-source share ≥95% gives 1.0, ≥50% gives 0.75, otherwise 0.5. No preset gives layout factor 0.5; a selected preset gives 0.75. These deliberately conservative deterministic tables are visible in the UI; ordinary observations are not proven authentic and a preset is not a verified physical mapping. Scope concentration is shown separately and controls the 70% default; it is not an extra score multiplier.

Fn unknown yields no trigger preview. Confirmed function keys and simpler command/control/option combinations are sketches only: backend capability/conflict validation is absent, and there is no apply or export action. Stateful shortcuts remain visible in statistics/all candidates with an explicit excluded status and no mapping controls. Unknown application buckets participate in weighted scope denominators. Reset summaries are not analyzed because they do not contain daily/source evidence. No new hashes, snapshots on disk or release gates were added.

The engine accepts the reducer's explicit active-day encounter order. Phase 1's
2026-09-29 persistence repair stores that daily order as a separate encrypted
cycle object before aggregate shards. Restart retains encounter order across
date rollback; cycle reset deletes the object with daily details. Legacy stores
without this object retain the previous chronological fallback because their
original encounter order was never stored. No historical order is reconstructed
from guesses. Full physical geometry/transform evidence and firmware candidate
paths remain deferred to qualified backend work.
