# 完整 v1 需求与剩余边界核对

核对日期：2026-10-20。本文按现行 PRD 的全部功能需求建立人工可读的实现与验证对应，不新增冻结清单或发布门禁。工程证据与真实支持资格分别记录；具体 PR/CI 以 [v1 执行计划](V1_DEVELOPMENT_PLAN_20261020.md) 为准。

## 功能需求覆盖

| PRD 要求 | 现有实现与离线验证入口 | 尚不能据此证明 |
|---|---|---|
| FR-C1–C5 首开、暂停/恢复、退出恢复、登录项、周期保留 | Core LifecycleOrchestrator、App ProductComposition；LifecycleTests、LifecycleRestartTests、LifecycleOrchestrationTests；应用后新周期提示保留删除前复核 | 新系统上的 TCC/登录项/锁屏/重开实际行为 |
| FR-C6–C8 按住计数、归属和失败关闭、持续快捷键 | Capture 归一化与隐私门、Core 聚合；Capture 与 PrivacyGateTests、离线 capture harness | 外部注入普遍识别、未测系统的安全输入和前台来源可靠性 |
| FR-P1 网络边界 | UpdateHTTPClient 唯一固定查询；PrivacyEgressTests、PrivacyBinaryAuditTests、UpdatesTests、Release 二进制审计 | 最新发布物实际网络/TLS 与分发资格 |
| FR-P2–P4 不存文本/键序、裸键最小化、排除失败关闭 | PrivacyBoundaryTests、PrivacySerializationTests、PrivacySchemaAudit、PrivacyGateTests | 来源无法判定时不能计数，也不借未知桶绕过 |
| FR-P5、FR-P7 加密与密钥生命周期 | ObjectStore、Keyring、产品精确 Keychain 项边界；Store 加密/故障/删除回归 | 新密码恢复流程的真实 Keychain、真实完整删除 |
| FR-P6、FR-BK3 备份与普通导出 | PasswordBackup、PasswordBackupModel、ConfigurationExportModel；PasswordBackupTests、FirmwareOperationTests、原生取消/撤销/覆盖拒绝测试 | 密码备份不是自动迁移或覆盖恢复，普通 JSON 不是官方后端导入文件 |
| FR-R1–R4 评分、资格、衰减、候选上限 | Analysis 评分、候选与投影、AnalysisDashboardView；KeyRecordAnalysisTests | 推荐不承诺真实速度或健康收益 |
| FR-R5–R7 声明、作用域、触发风险 | 候选解释/作用域与风险确认、RecommendationDraft；CandidateConstraintTests、RecommendationDraftTests、原生草稿回归 | 不把组合/应用推荐改成固件基础键后声称语义等价 |
| FR-E1 几何与证据链 | PhysicalSourcesModel、系统/Karabiner/Vial 适配器、设备布局匹配、VIA/Vial 定义解析；Physical*Tests 与官方 reader 对照 | 复杂形状、历史设备归属、活动层/时序、软件实际执行顺序不完整时回退逻辑口径 |
| FR-E2 布局询问时机 | Analysis 状态与已保存偏好；PreferencesTests、分析及原生流程回归 | 没有几何不自动推断用户物理键盘 |
| FR-BE1–BE3 Karabiner 事务、隔离与外部修改 | KarabinerTransactionCoordinator、文件事务与部署模型；KarabinerFileTransactionTests、KarabinerMappingTests、崩溃子进程与原生回归 | 真实后台重载、Profile 切换与生效；生产支持目录仍按真实证据解锁 |
| FR-BE4、FR-BE8 VIA 层与选槽 | VIA 文件编辑器、层入口/可达性保护、字节修补；VIAImportFlowTests、FirmwareOperationTests、官方方法离线往返 | 不能在无最新基线时输出；不新增层或占用受保护入口 |
| FR-BE5 版本阻断 | 独立格式/定义/导入器来源与后端能力检查 | 文件兼容不赋予真实设备或未知版本支持资格 |
| FR-BE6 Vial 非变更查询 | DeviceRead 白名单传输、定义/配置读回工厂；DeviceReadTests、Vial*Tests | 真实 HID、断连行为和至少三款设备覆盖 |
| FR-BE7 不透明内容保留 | 原件加密保存及仅选槽位字节修补；固件往返/宏/未知字段回归 | 不生成或解释未知高级动作，不把合成读回视为官方 GUI 效果 |
| FR-M1–M2 创建流程与草稿独立 | 推荐候选→后端/配置/作用域→草稿→冲突→确认，Karabiner 与固件独立状态；原生映射与导入测试 | 受后端真实表达能力限制，固件路径不提供应用专属或组合语义 |
| FR-M3–M4 阻断与二次确认 | CandidateConflictDetector、准备上下文重新检查、高风险确认；CandidateConflictDetectorTests、原生应用按钮/来源失效测试 | 外部应用实际效果不能仅凭静态冲突扫描保证 |
| FR-M5 权限降级 | MenuShortcutsModel 的显式选择/读取、临时菜单证据、权限拒绝回退；中英文原生按钮与准备失效回归 | 真实 AX 权限和第三方菜单覆盖；字符/字形快捷键仍是部分证据 |
| FR-A1 状态与验证来源 | 映射/固件批次记录与界面；导出、导入声明、读回状态分开，原生状态回归 | 声明导入不等于已验证；配置一致不等于应用效果 |
| FR-A2 临时规则清理 | 行为测试会话开始/完成/取消/失败、退出清理、重开协调；临时配置与模拟端口回归 | 真实测试快捷键效果与实际进程退出/重载时序 |
| FR-A3 一键停用 | 菜单栏与 Karabiner 部署停用/恢复；事务与原生按钮测试 | 支持版本真实停用 p95 ≤2 秒 |
| FR-A4 卸载准备 | 恢复副本先行、删除前重新检查、受管规则/登录项/本地数据步骤；临时文件及恢复选择回归 | 真实卸载、真实密钥清除、用户日常配置不受损 |
| FR-BK1–BK2 保留规则 | Karabiner 滚动十份、固件恢复副本显式删除；Store/Mapping 回归 | 不可用已有文件覆盖导出，不自动删除固件唯一恢复副本 |
| FR-U1–U2 菜单栏与克制通知 | 默认无 Dock、可选 Dock 偏好、推荐徽标、主窗口入口；原生与偏好保存失败回归 | 新系统菜单栏、窗口和辅助功能实际体验 |
| FR-U3–U5 双语、可访问性、命名 | NativeText/本地化资源、原生控件 AX、默认快捷键/应用名及用户改名；LocalizationAudit、原生中文/英文测试 | 离线 AX 断言不等于完整 VoiceOver 和纯键盘实机验收 |
| FR-S1 系统兼容 | macOS 14 最低编译目标、Universal 构建；当前生产锁屏来源仅启用 arm64 macOS 27+ | **仍有平台来源阻塞**：旧 macOS/Intel 不能靠通过编译就开启安全采集，需要先证实可靠来源，再接入/启用并验证 |
| FR-S2 资源预算 | 既有测量工具和限定候选实测保留；模拟计算测试 | 最新功能版本、Intel 和跨系统的规定时长 CPU/内存测量 |
| FR-S3 单进程 | 唯一 App target、无助手/daemon、源码与包结构边界测试 | 实际发布物启动/进程检查 |
| FR-S4–S5 更新确认与无遥测 | 每周固定查询、显式确认打开官方页、手动安装；模拟 HTTP、时钟、取消与原生确认 | 真实版本页、下载、签名校验与安装链路 |
| FR-S6 签名公证 | release-package.rb 计划/执行路径和失败保留；模拟命令验证先签名检查、公证、staple、评估，再打最终 ZIP | 真实 Developer ID、公证、Gatekeeper、下载后首次启动；尚未发布 |

## 哪些确实只能先等真实验证

1. Karabiner 支持版本的实际重载、应用专属行为、退出清理及停用延迟。
2. VIA 官方 GUI 导入后的按键效果；Vial 真实只读 HID、断连/重连、实际设备与固件版本组合。
3. 新备份恢复链的真实 Keychain、恢复副本可用性和完整卸载。
4. 可选菜单读取的真实 AX 授权、双语/纯键盘/VoiceOver，以及新版本性能。
5. 签名、公证、分发、更新页、安装与首次启动。这些不能由模拟脚本或 CI 批准。

## 哪些不能叫“只差验证”

- FR-S1 的 macOS 14+ 双架构目标尚未完整实现为可用生产采集路径。ObservedSessionLockProvider 当前有平台限制；需要先在目标平台确认可靠的锁屏/前台/安全输入来源，必要时补适配器。禁止直接移除限制或用“可编译”充当运行资格。
- 历史逐事件设备、层状态、按住时长与软件执行顺序没有足够来源。现有聚合无法事后还原；当前正确行为是逻辑回退。若希望新增这些分析能力，必须单独确定未来采集范围与隐私语义，当前授权不包含扩大采集。
- 复杂/不支持的几何、未知高级固件动作仍明确拒绝或回退；不能把受限编辑器描述为完整 VIA/Vial 配置编辑器。

因此，可离线工程闭环与完整 v1 达标不是同一个结论。下一步应先处理平台来源证据与受控真实验证，依据发现定向修复；不恢复自动续轮，也不为制造“进度”新增检查机制。
