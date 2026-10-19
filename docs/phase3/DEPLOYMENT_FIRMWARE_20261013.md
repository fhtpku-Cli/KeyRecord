# 部署会话与固件核心工程增量

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

> 本记录保存前一增量当时的范围与证据。后续用户已明确授权原生卸载源码，入口及固件界面在[新增量](NATIVE_UNINSTALL_20261013.md)完成；本文的 UI 审批拦截不是当前阻拦。

日期：2026-10-13，Asia/Shanghai。源码提交：

`7d4a3a195f0bc53d0c7156f43d2c9f637eed8653`。

本批基于 PR24 的源码与记录继续开发，已通过普通 merge 衔接 PR24 合并提交 `853b0b95bcd273b787006221cf913ffa2cc492ac`；merge 没有改变本批文件内容。主目录仍为 `64590a0e9`、215 项历史/其他改动，只在本任务隔离 worktree 开发。

**已完成本批部署会话接线、固件修补/日志核心和恢复副本界面；尚未完成完整 Phase 3/G3 或 Phase 4/G4。卸载原生执行入口被自动审批拦截，串联核心仅通过注入端口验证。** 生产支持目录保持为空，实际 Karabiner 写入和固件生成没有获得资格。

## 部署会话

默认 ProductComposition 已连接 KarabinerDeploymentModel、现有受保护 ObjectStore 和 KeyAvailabilityGate。用户选择“准备应用”后才打开原生文件选择器；会话绑定所选目标及完整唯一 Profile 名称，读取配置并执行现有事务对账，再加密保存目标书签、位置、Profile 和事务命名空间。副本导入不建立写入资格。

版本端口可注入。默认端口读取已安装应用的 Info.plist 元数据，不启动或安装后端；包身份依据 [Karabiner 官方构建配置](https://github.com/pqrs-org/Karabiner-Elements/blob/main/src/apps/SettingsWindow/project.yml) 与 [版本资源模板](https://github.com/pqrs-org/Karabiner-Elements/blob/main/src/apps/SettingsWindow/Resources/Info.plist.in)。本轮没有在用户机器调用默认版本端口，测试全部使用注入版本。因此这里只确认接线和拒绝策略，不宣称已检查本机安装。

生产目录没有版本/Profile 资格记录时，连接可只读打开目标、预览和导出，明确展示支持目录为空。UI 没有支持版本勾选或清单输入。临时测试依旧使用 temporaryConfiguration，并受 KarabinerFilePort 的临时目录限制；这不是生产资格。

隐私关闭撤回运行上下文、文件监测、配置端口和原生状态；恢复可见后，从加密引用重新打开并对账。原子替换会使文件书签变旧，因此重开时校验解析位置与加密绑定位置相符，并继续通过普通文件/所有者/单链接/拒绝符号链接/有界 JSON 的读取端口。书签跟随目标移动不能静默改变绑定。

目录事件监测覆盖原子替换；事件撤回准备结果和风险确认，并刷新事务状态。在操作中到来的刷新保留到操作结束。当前版本/上下文在 canApply、canManage 和事务提交时重新读取；旧检查不放行变更后的版本。存在仍受管的旧目标或未完成事务时拒绝重绑定，保留旧会话的管理入口。只读会话仍可以检查配置、采纳或明确停止管理；会写文件的重新应用、停用、恢复、回滚与移除继续受写入资格约束。菜单栏既有停用入口消费同一模型。

## 固件核心及恢复副本

FirmwareDocument 使用现有有界 JSON 范围解析器。VIA 与 Vial 分开解析身份和槽位形状；Vial UID 保留原始十进制/字符串身份，避免浮点转换。批量修补只替换选中槽位的原始范围，其余字节不序列化；宏和未知子树原样保留。

生成需要设备身份及定义 schema、设备协议、布局格式、键码方言、官方导入器五个明确版本轴与支持目录完全匹配。默认目录为空，原生副本保存将这些未知轴保留为 nil，用户声明“这是最新官方导出”不会补齐资格。只允许目录支持的标准键/修饰组合输出，不生成动态高级动作。自动槽位只使用 KC_NO，KC_TRNS 保持占用；自动层只允许基层的一步 MO/LT，手动层按已有入口可达性检查。既有层入口、复位和 Bootloader 槽拒绝替换，不新建层或修改入口。

FirmwareOperationCoordinator 将原始基线、产物和操作元数据分别保存到现有加密对象存储。来源/产物 SHA-256 沿用 PRD V3/A5 与架构 §9.5 的既有文件一致性要求，没有新增支持资格摘要、冻结 contract、baseline 清单或发布 gate。外部文件跨出对象存储事务，路径、书签与操作阶段仅在加密日志中持久化。

产物就绪、目标记录、写出读回、声明导入、行为证据和放弃产物均有日志阶段。中断后只补全已经记录、并与当前文件一致的事实；外部文件缺失或改变不写回覆盖、不伪造导入或验证。重复导出复用同一批次的相同产物；不同批次保留独立原始副本。放弃未导入产物保留原始副本，固件副本不套用 Karabiner 的十份滚动清理。孤儿仅按这两个固件对象类型和已记录批次清理。

等待用户导入、用户声明已导入、VIA 用户行为测试确认、失败及引导回退分别记录。声明导入永远不设置 verifiedAt。当前没有实际 Vial 查询/读回证据提供器，不能产生 Vial 设备验证。

默认原生设置已提供加密保留选中的 VIA 原始副本、列表、状态和恢复副本导出。导出前明确说明文件会明文包含固件宏且不含统计，恢复方式为经官方 VIA/Vial 导入原始备份。原生事件带会话票据，文件来源变更或隐私关闭后的晚到保存/导出拒绝；副本原文在隐私关闭时撤回。Vial 修补及状态核心已离线执行，Vial 文件选择、实际版本发现和完整生成/导入/验证 UI 仍是后续工程。

## 卸载准备与审批限制

UninstallPreparationCoordinator 已实现顺序：保障每份固件恢复副本（实际导出读回、用户明确另行持有、或明确放弃并记录）→ 移除受管规则 → 移除登录项 → 按用户选择保留或删除本地数据。阶段和选择先加密记录；任何步骤失败或既有隐私代次失效都会停止后续副作用。恢复准备期间复用固件协调器串行机制，拒绝加入新批次；删除数据前再次确认恢复副本仍与原件一致。不会仅因前置检查通过就假定副作用成功。

所有卸载测试的规则/登录项/数据端口都是注入端口；恢复副本写到任务临时目录。未执行真实卸载、真实登录项移除、日常钥匙串或数据删除。

自动审批两次拒绝加入能够触发规则/登录项移除和数据擦除的原生 UI，理由为当前可见的可信用户授权不足。第二次重试前已只读核对原始工程授权，仍被拒绝。没有改用其他工具绕过。被拒绝的 UI 补丁未落地；生产卸载执行入口与副本删除 UI 仍未连接，需用户对这项源码开发明确确认。可审阅的串联核心、测试、恢复副本界面已交付，不能据此宣称 FR-A4 全部完成。

## 本批验证与自审

共 **75 项不同的相关场景最终通过：49 项 SwiftPM、26 项 App**。未签名 arm64 build-for-testing 通过。没有重跑 Phase 1 网络观察或实机验收，也未建立新的实机资格。

| 范围 | 已观察的行为 | 证据 |
|---|---|---|
| 部署/原生映射与恢复副本 | 14 项：加密目标、隐私重开、只读拒绝、保留旧绑定、外部原子替换、版本变化、晚到副本动作、正常/拒绝路径和双语原生按钮 | /private/tmp/keyrecord-observations-final-native.log；/private/tmp/keyrecord-observations-final-qa/deployment-copies-en.png 与 deployment-copies-zh-Hans.png |
| 既有副本读取 | 10 项：符号链接/FIFO/目录/大小、隐私、晚到请求、文件变更及原生参考 | /private/tmp/keyrecord-deployment-app-final.log |
| 双语和 Xcode 图 | 各 1 项 | /private/tmp/keyrecord-deployment-localization-final.log；/private/tmp/keyrecord-deployment-app-final.log |
| 固件与卸载核心 | 12 项：多槽修补、五轴/空目录拒绝、Vial 不透明保留、加密导出/重导出/声明/证据、各日志阶段磁盘重开、缺失/外部编辑、文件保护、12 份原始副本、卸载顺序/故障/隐私/恢复副本变更/并发新批次 | /private/tmp/keyrecord-firmware-reviewed.log |
| 相邻事务与边界 | 16 项 Karabiner、8 项 VIA 解析、4 项序列化、6 项模块边界 | /private/tmp/keyrecord-deployment-boundaries.log |
| 原有无联网能力扫描 | 3 项，包括 CI 实际失败的产品扫描 | /private/tmp/keyrecord-deployment-egress-fixed.log |
| 构建 | 未签名 arm64 App 与测试 bundle | /private/tmp/keyrecord-observations-final-build.log |

原生测试通过 NSHostingView 和真实辅助功能按钮执行，不是只检查 View 源码；主会话已查看双语截图。库端通过公共 API 驱动真实临时文件、原子替换、加密磁盘保存/重开及异常路径。日志与临时截图可能随清理过期。

失败与修复记录：第一次 Xcode 因沙箱拒绝默认编译缓存而失败，获准构建缓存后通过。文件监测回调继承主线程隔离，在后台触发 dispatch_assert_queue 崩溃；显式 Sendable 回调后同一真实文件事件不再崩溃。原子替换导致书签变旧/规范路径不同，曾使隐私重开和重绑定拒绝测试失败；位置绑定及父路径规范化后同一场景通过。多份副本共用 AX ID 被原有唯一性检查识别，改为批次 UUID 身份后原生用例通过。初次扩大选择整个 AppProjectTests 时，Universal 产品用例因未提供 T23_RELEASE_APP 失败；本批不修改或削弱该用例，最终只运行相关产品图用例，不将未执行的 Universal 验收记通过。初次本地化选择使用了文件名而非扩展所属类，未执行该用例；更正为 ScreenMatrixTests 后实际 1 项通过。

自审修复的两个具体风险是：重绑定拒绝不应丢掉仍可用的旧目标管理入口；恢复副本导出后若在卸载准备期间被编辑，不能继续擦除本地原件。另用并发反例确认准备期间不能加入没有恢复选择的新批次。测试和原有审计保持精确登记，没有删除用例或放宽规则。

| Lane | Exact source commit | Verdict | Report / artifact |
|---|---|---|---|
| Main-session manual QA | 7d4a3a195f0bc53d0c7156f43d2c9f637eed8653 | PASS，限已交付的离线工程范围 | 本表、原生动作日志与双语截图、固件磁盘/API 场景日志 |
| Main-session self-review / runtime audit | 7d4a3a195f0bc53d0c7156f43d2c9f637eed8653 | PASS，限已交付范围；完整任务仍有上述 UI 审批阻拦 | 本记录的失败/修复与范围说明；最终差异及 git diff --check |

普通 merge 未改变源码文件树；随后 CI 修复仅更名本地会话方法，13 项受影响原生场景、3 项原有联网能力扫描及未签名构建已重新通过，其余未受影响项复用本表结果。review-work 按 Codex 主会话自审规则执行，没有声称独立审查或真实后端合格。

其后的运行时反例复现：检查后新增冲突观测，运行上下文仍缓存旧观测，旧检查允许临时配置从 88 字节写为 485 字节。同一用例两处断言失败；日志为 /private/tmp/keyrecord-observations-conflict-before.log。修复在观测发布与 canApply/canManage 判断时同步受保护的当前观测，旧准备上下文不再匹配；重新检查后需要重新确认风险。最终 14 项原生场景通过，包括该反例及风险确认断言；三项原有联网能力扫描再次通过（/private/tmp/keyrecord-observations-egress.log），未签名最终构建通过。没有降低冲突级别或复用旧风险确认。

首轮 [push CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38317706482) 和 [PR CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38317798221) 均失败。push 日志实际执行 665 项包用例，失败为 PrivacyEgressTests 在两个 App 文件报告共两处断言失败：新增本地方法名 connect 命中了既有 socket 名称禁用扫描。将方法准确更名为 openTarget / attachReconciled 后，原有扫描与相邻原生路径通过；没有修改扫描器、放宽白名单或删测试。失败日志为 /private/tmp/keyrecord-deployment-ci-failure.log。修复后的远端 CI 以实际运行结果为准。

实际配置/设备、真实支持矩阵、官方导入器、重载/效果、停用 ≤2 秒 p95、至少三款真实键盘、签名公证和 FR-P6 等仍缺失。完整 G3/G4、FR-A4 与公开发布保持未完成。
