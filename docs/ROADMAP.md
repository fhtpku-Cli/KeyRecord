# 路线图与当前交付状态

状态日期：2026-10-15，Asia/Shanghai。增量 A 的主体已由 [PR #19](https://github.com/fhtpku-Cli/KeyRecord/pull/19) 合并为
`adae0c4e429ff2c955b978f67a0afd069ce7708c`，[主干 CI 通过](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38246915859)。
B 的工程基础及只读 VIA 参考已由 [PR #21](https://github.com/fhtpku-Cli/KeyRecord/pull/21) 合并为 `2c29f18e6`。开发签名 arm64 隔离试用包和短流程已准备，实际试用未执行；见 [准备记录](phase2/TRIAL_PREPARATION_20261013.md)。不增加新门禁或实机验收轮次。

## Phase status

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
| Phase 4: VIA/Vial Beta | **离线兼容与生产组合接入已实现；未合格** | 矩阵、编码器及四类动态条目已接通只读验证；层入口保护保留。VIA 可显式读取独立设备协议/键码版本，但定义与在线导入器版本仍未知。空支持目录继续阻止未合格映射生成及 Vial 读回打开设备；VIA 版本检查仅只读。宏、布局选项、QMK 设置、未知动态表示及真实 GUI/设备证据继续后置。见[最新读回批次](phase4/DYNAMIC_READBACK_20261015.md)。 |
| FR-P6 full password backup | **密码备份及空资料库恢复工程已实现** | 全部已保存对象独立密码加密，原子恢复到独立本地密钥；已有资料库不可覆盖，原删除前复核保留。真实 Keychain 恢复和 Intel 计时后置。[实现与边界](PASSWORD_BACKUP_20261015.md)。 |
| Full v1 / public distribution | **Not qualified** | PRD §15 requirements, real backup/restore qualification, Intel/full support matrix, public name/license decision, signing/notarization and backend requirements remain. |

Requirements remain in [PRD](PRD.md) and [architecture §15](TECHNICAL_ARCHITECTURE.md#15-分阶段交付与发布门禁).

2026-10-13 最新增量为[Vial 6 协议与官方格式离线集成](phase4/BACKEND_OFFLINE_INTEGRATION_20261013.md)，47 项相关离线测试通过，并实际执行官方源码保存/恢复方法及公开 API 驱动。正式支持目录仍为空，文件只能提供部分版本事实，实际 HID 端口未启用；真实设备/版本矩阵和发布证据继续后置。下文保留前序批次范围。

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
