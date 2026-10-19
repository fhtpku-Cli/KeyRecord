# 路线图与当前交付状态

状态日期：2026-10-19，Asia/Shanghai。当前处于主要底层工程已实现、完整用户流程继续收尾的阶段，不能宣称完整 Phase 3/4 或公开发布合格。下表及“下一步”是当前计划；日期记录中的待办只描述当时范围。

## Phase status

2026-10-19 VIA 文件编辑流程：从加密保存的最新原始副本列出实际层、位置和原按键，使用具名基础键选择代替手写键码。层入口、未知动作和不可达层可查看原因但不能加入修改；预览与导出再次执行既有核心校验。导出后显示手动导入、实际按键检查及恢复指引。不提供无依据的物理键盘图，不把文件改键扩为快捷键或应用专属映射。见[本批范围](phase4/VIA_GUIDED_FILE_EDITING_20261019.md)。

2026-10-17 固件文件处理耗时：修复大量缺失层引用触发重复全表扫描的问题；相同离线 Debug 样本的四次改键检查由约 24.8 秒降至 2.9 秒，兼容判断、层入口保护与输入限制不变。见[实际测量与边界](phase4/FIRMWARE_REACHABILITY_SCAN_20261017.md)。

2026-10-16 VIA 层跳转边界：修复异常文件中 `LT(16…31,KC_A)` 被误认作可达层的问题；官方转换会把这些编号截回 0–15，现在预览和导出均拒绝依赖该错误入口的修改，正常 `MO(31)` 仍可用。见[复现与验证](phase4/VIA_LAYER_TAP_BOUNDS_20261016.md)。

2026-10-16 VIA 文件改键正式入口：已将文件编辑兼容范围与设备资格分开，最新配置可经加密保留、改键预览、导出，再由用户手动导回 VIA。90 个基础输出键码通过 9 类官方字典及实际官方导入函数离线对照；未知动作、层入口、恢复副本和删除前复核保护保留。旧记录不自动放行，真实设备支持目录仍为空。见[范围与复现](phase4/VIA_FILE_EDITING_20261016.md)。

2026-10-16 VIA 层与修饰键组合入口：补齐 `LM(...)` 的覆盖保护，既有官方离线转换回归扩展至 20 个场景；不扩展可生成输出或层可达性。见[复现与范围](phase4/VIA_LAYER_MOD_ENTRIES_20261016.md)。

2026-10-16 VIA Fn 层入口：补齐官方导出名称 `FN_MO13`／`FN_MO23` 的覆盖保护，阻止手动改键破坏这些层入口；新增 10 个实际执行官方转换函数的离线往返场景并接入 CI。见[复现与范围](phase4/VIA_FN_ENTRIES_20261016.md)。

2026-10-16 删除前复核：修复恢复副本在最后一次进度保存期间变化后仍进入删除的问题；保留原检查，并在保存删除意图后再次复核。临时文件覆盖内容变化、文件移走、父目录替换和重新选择后的重试。见[复现与边界](phase4/RECOVERY_FINAL_RECHECK_20261016.md)。

2026-10-16 导入来源失效：修复替换父目录后旧配置／定义参考仍可用的问题；取用参考时核对已选文件的身份与修改状态，检测到变化就撤销，原路径恢复也不会复活旧选择。定义单独失效不撤销配置文件概况。见[复现与边界](phase4/IMPORT_SOURCE_REPLACEMENT_20261016.md)。

2026-10-16 固件导出安全：修复已选父目录被替换后，文件导出可能写入同名新目录的问题。VIA／Vial 文件及恢复副本导出现在绑定选中时的目录，正常的同目录文件原子替换仍可用。见[复现与修复](phase4/FIRMWARE_EXPORT_DIRECTORY_20261016.md)。

2026-10-15 VIA 文件工作流：按用户选择，以主动导出最新配置、导入 KeyRecord、手动导回 VIA 为方向，浏览器运行实例绑定不再作为此前提。只导入配置即可显示按键概况；键盘定义用于补充矩阵核对与几何参考。本批未放开未合格的修改生成，真实验证边界保留。见[产品方向与本批范围](phase4/VIA_FILE_WORKFLOW_20261015.md)。

2026-10-15 VIA 来源撤销：清除或重新选择副本会立即关闭旧版本读取；重新选择相同字节也不能恢复已撤销操作的权限，迟到结果不再保存为新记录。已通过真实导入模型与模拟端点复现并完成原生回归，浏览器来源绑定仍未接入。见[复现与修复](phase4/VIA_SOURCE_WITHDRAWAL_20261015.md)。

2026-10-15 VIA 定义解析：原始定义遇到未知布局字段时，现在与编译定义一样保留键位参考、撤销几何测量并展示限制；修复前已复现错误的坐标与位置计数。见[复现与验证](phase4/VIA_RAW_LAYOUT_GEOMETRY_20261015.md)。

2026-10-15 VIA 来源选择：新增 10 个直接执行官方选择器的离线场景，覆盖自定义定义覆盖目录、同型号设备／独立会话、断连、版本选择及布局选项变化。已证明目录下载与 VID/PID 不能替代当前实例的有效定义来源；真实浏览器会话采集及导入器运行版本仍未接入。见[实际执行与后续边界](phase4/VIA_ACTIVE_SOURCE_SELECTION_20261015.md)。

2026-10-15 离线回归自动化：CI 接入 11 份官方方法生成夹具对照、9 类加密事务／官方恢复往返，并实际执行固件原生回归及生产组合测试；拒绝 XCTest 选择器失效导致的零测试假成功。现有包测试与未签名构建保留。见[执行范围与复现](phase4/OFFLINE_REGRESSION_AUTOMATION_20261015.md)。下列增量段落保留各批当时的范围，当前剩余缺口以下表为准。

2026-10-15 动态读回增量：Tap Dance、Combo、Key Override、Alternate Repeat Key 四类动态条目已实际按只读协议读取，并完成官方方法离线对照、全量条目比对和加密中断恢复。VIA 新增显式设备版本读取入口；协议 13 可独立读取键码版本，旧协议仅记录协议号。宏缓冲、布局选项、QMK 设置及未知动态表示仍待实现；VIA 在线导入器版本不可由桌面外壳版本替代。真实验证继续后置，见[实现与边界](phase4/DYNAMIC_READBACK_20261015.md)。

2026-10-15：完整密码备份/空资料库恢复已实现；Phase 3/4 的生产组合现已传递后端依赖，并接通显式 Vial 设备选择。未知支持仍只读，真实设备与卸载验证继续后置，见[接入范围](phase4/HOST_INTEGRATION_20261015.md)。下表 Phase 4 的早期批次数量仅描述该批，不代表累计覆盖。

2026-10-15 后续：Vial 定义读回补齐 KLE 对齐状态、装饰键和首项元数据，14 组官方源码生成的拓扑用例匹配；完整读回仍核对装饰键涉及的矩阵位置及编码器，见[本轮记录](phase4/DECORATED_DEFINITION_20261015.md)。真实设备资格与动态子协议继续后置。

2026-10-15 安全增量：Phase 3 配置会话绑定已打开的父目录，目录替换不能把读写、临时文件清理或同步重定向到替代目录；原生操作资格与刷新同步识别失效目标。正常的同目录文件原子替换仍可用，见[复现与修复](phase3/DIRECTORY_BINDING_20261015.md)。真实设备、Keychain 恢复和卸载验证继续后置，删除前复核保留。

2026-10-15 Phase 4 验证范围：包含动态配置、设置或未知字段的 Vial 副本，键位与编码器匹配只记作“部分验证”；旧记录和中断恢复同步修正，原始内容逐字节保留。生产组合新增本机 Vial 应用版本／构建信息来源及变更失效处理，支持目录仍为空。动态子协议实际读回、VIA 独立版本来源及真实验证仍待后续，见[范围与来源](phase4/VERIFICATION_SCOPE_20261015.md)。

| Phase | Current state | Remaining scope / evidence boundary |
|---|---|---|
| Phase 0: feasibility | Capture prerequisites progressed beyond the old G0 OPEN writeback; historical artifacts remain unchanged | Karabiner version/reload/disable latency, VIA protocol/dialect/importer, Vial importer/live capture and backup KDF/Intel evidence retain their own limits. Phase 0 is not globally all-green. |
| Phase 1: collection, privacy, encrypted storage | **Approved Apple Silicon MVP complete and merged** | Measured arm64 macOS 27.0 build 26A428 only; development-signed local trial. Existing candidate-specific short ARM and lifecycle evidence retained. Full original G1/v1, all OS/architectures and public release are not claimed. |
| Phase 2：确定性分析 | **A/B 工程开发与离线自审完成；真实 G2 证据后置** | 能力过滤、范围明确的冲突检查、特殊键池、手动候选、物理链消费/回退与只读副本已接通。实际后端、完整真实部署/变换链、系统选择器授权和真实保存重开集中留后；产品不冒充已连接或真实物理收益。 |
| Phase 3: Karabiner stable path | **部署会话和原生卸载工程增量完成；完整 G3 未完成** | 目标绑定、加密引用、隐私重开和外部监测已接通；暂停捕获→逐份恢复副本→规则→登录项→数据选择的默认卸载准备及阶段显示已离线执行。历史阶段仅供检查，维护期间后台对账延后并恢复。空生产支持目录只读，真实版本、重载、效果和停用 p95 后置。[本批记录](phase3/RECOVERY_CHOICES_20261013.md)。 |
| Phase 4: VIA/Vial Beta | **VIA 文件改键入口与离线读回工程已实现；真实设备未合格** | VIA 可在明确的基础键码范围内保留、预览并导出修改文件，由用户手动导入检查；不依赖浏览器实例绑定，不推断设备资格或物理位置。原始及编译定义仍用于参考。Vial 的矩阵、编码器、四类动态条目、宏、布局选项及 QMK 设置已接通只读协议与离线验证；未知表示保持部分验证。空设备支持目录继续阻止未合格设备操作，真实 GUI 导入、HID 和键盘效果后置。见[文件入口](phase4/VIA_FILE_EDITING_20261016.md)及[配置读回](phase4/CONFIGURATION_READBACK_20261015.md)。 |
| FR-P6 full password backup | **密码备份及空资料库恢复工程已实现** | 全部已保存对象独立密码加密，原子恢复到独立本地密钥；已有资料库不可覆盖，原删除前复核保留。真实 Keychain 恢复和 Intel 计时后置。[实现与边界](PASSWORD_BACKUP_20261015.md)。 |
| Full v1 / public distribution | **Not qualified** | PRD §15 requirements, real backup/restore qualification, Intel/full support matrix, public name/license decision, signing/notarization and backend requirements remain. |

Requirements remain in [PRD](PRD.md) and [architecture §15](TECHNICAL_ARCHITECTURE.md#15-分阶段交付与发布门禁).

## 下一步（2026-10-19 复查）

本批只交付 VIA 文件编辑流程及状态文档，完成后汇报；不自动启动下一批，不恢复定时续轮。

1. 后续优先接通 Karabiner 应用行为测试会话：开始、结束、取消、失败和异常退出清理。现有原生验证入口只做配置读回，核心临时规则及恢复机制不能替代完整产品流程。工程可先在临时配置和模拟端口验证。
2. 再补推荐到后端草稿的衔接：当前推荐创建仅接 Karabiner；VIA/Vial 是独立编辑流程。按真实能力传递目标、触发及作用域并重新检查，基础单键编辑不能冒充组合快捷键或应用专属映射。
3. 完整物理成本仍缺生产来源连接：固件、软件及 macOS 变换链缺失时继续使用逻辑口径。来源接入与真实资格分别处理，不把配置文件当设备事实。
4. 真实验证集中后置：Karabiner 重载/效果/停用 p95，VIA 官方 GUI 导入/键盘效果，Vial HID/断连/读回及键盘覆盖，Keychain 恢复、真实卸载、完整平台与发布验证。生产支持目录仍为空，删除前复核保留。

本计划不新增 hash、冻结 contract、baseline 或 gate，也不以离线回归通过替代既有真实验证要求。

## 历史阶段说明（不是当前待办）

2026-10-13 最新增量为[Vial 6 协议与官方格式离线集成](phase4/BACKEND_OFFLINE_INTEGRATION_20261013.md)，47 项相关离线测试通过，并实际执行官方源码保存/恢复方法及公开 API 驱动。正式支持目录仍为空，文件只能提供部分版本事实，实际 HID 端口未启用；真实设备/版本矩阵和发布证据继续后置。下文保留前序批次范围。

2026-10-13 最新开发结论：**增量 B 工程开发与离线自审已完成**，后端能力过滤、观测/系统风险/规则重叠/映射环/保护入口检查及证据失效已接通产品；见 [完成记录](phase2/B_COMPLETION_20261013.md)。正式 G2 的真实证据仍后置，下一阶段的工程开发进入 Phase 3。下列早期试用安排仅保留历史范围，当前不要求执行那一轮试用。
Current Phase 1 evidence is in [acceptance](PHASE1_ACCEPTANCE.md), not the old T24
projection or the baseline-bound `milestone-allocation.json`.

## 已确认的 Phase 2 方向与当时工作安排（历史）

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
