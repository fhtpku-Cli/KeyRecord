# 原生卸载准备与固件流程增量

日期：2026-10-13，Asia/Shanghai。源码提交：`e4cb2fc981665c12e3ab3ac5dbcaaac395cbb0a2`。

用户已明确授权补齐固件副本删除、受管规则及登录项移除、本地数据选择，并继续无需真实验证的工程。范围限源码、合成输入、注入端口和专用临时目录。没有执行真实卸载、真实数据/Keychain 删除、键盘读写、日常配置修改、实际捕获或公开发布。主目录复核仍为 `64590a0e9b57a55af9a23921983f2c16bb59c62e`，215 项历史/其他改动；本批只修改任务 worktree。

## 实现

- 默认产品组成接入卸载准备：先处理每份固件恢复副本，再移除受管规则、移除登录项，最后按选择保留或清除本地数据。本地数据默认保留；逐份导出使用原生保存选择器和读回，取消不会继续。另存声明与明确放弃分别记录。
- 页面内独立确认后才删除选定原始副本或执行准备；副本仅可在 draft/rolledBack 状态删除。确认票据在隐私关闭后失效。准备期间阻止相邻规则、登录、重置和全删操作；已有目标、登录或危险操作未结束时不开始准备。
- 登录移除使用会抛出错误的生命周期方法，并持久保存 loginItemEnabled=false；任一失败阻止后续清除。原生适配器在显式移除时读取一次状态，已移除直接完成；macOS 15+ 的精确 ServiceManagement job-not-found 结果亦视为已移除。签名、授权及其他域错误继续失败关闭。没有后台状态轮询。
- 清除数据复用既有 ProductDestruction、停采集/写入排空/失败恢复路径和返回首次同意的生命周期。完成后只显示通用卸载准备提示；不重新发布旧敏感数据，不自动退出或删除应用。用户之后自行退出并移到废纸篓。
- Vial 原始文件入口复用有界、禁止符号链接的受保护读取；精确 UInt64 UID 和不透明宏/未知子树原字节保留，原始副本加密存储并可恢复导出。
- 接入已合格批次的槽位修改导出、导入声明、VIA 行为测试结果、放弃导出和恢复声明。导出、声明、证据时间分别显示；导入声明不会变为 verified。未知轴和空生产目录无法生成修改，用户不能在界面自行授予资格。测试目录与轴仅注入合成夹具。
- Vial 当前没有实际设备读回端口，导入保持未验证。恢复声明仅记录用户通过官方导入器恢复原始文件，不声称 KeyRecord 写入或自动验证固件。

## 离线证据

107 项不同相关场景最终通过：70 SwiftPM、37 App。未签名 arm64 build-for-testing 通过。没有新增 hash、冻结 contract、baseline 或执行 gate，没有删除用例、放宽原有隐私扫描或改变正式发布资格。

| 范围 | 实际用例数 | 日志 |
|---|---:|---|
| 固件核心与真实临时文件 | 12 | /private/tmp/keyrecord-uninstall-final-core.log |
| Karabiner 文件事务 + 核心事务 | 4 + 12 | /private/tmp/keyrecord-uninstall-final-core.log；/private/tmp/keyrecord-uninstall-karabiner-regression.log |
| VIA 解析 | 8 | /private/tmp/keyrecord-uninstall-final-core.log |
| 隐私序列化、联网能力、模块边界 | 4 + 3 + 6 | /private/tmp/keyrecord-uninstall-final-core.log；最终联网复核 /private/tmp/keyrecord-uninstall-complete-egress.log |
| 生命周期及登录偏好 | 14 | /private/tmp/keyrecord-uninstall-final-core.log |
| 原有生命周期结构/系统端口边界 | 7 | /private/tmp/keyrecord-uninstall-ci-fix-core.log |
| 部署/固件模型和真实原生按钮 | 23 | /private/tmp/keyrecord-uninstall-complete-native.log |
| 默认产品组成卸载：保留/清除、登录失败停止 | 2 | /private/tmp/keyrecord-uninstall-complete-native.log |
| 相邻导入、本地化、产品图 | 10 + 1 + 1 | /private/tmp/keyrecord-uninstall-complete-native.log |

最终构建日志：/private/tmp/keyrecord-uninstall-ci-fix-build.log。最终 37 项 App 日志：/private/tmp/keyrecord-uninstall-ci-fix-native.log；7 项结构/端口、14 项生命周期和 3 项联网审计日志：/private/tmp/keyrecord-uninstall-ci-fix-core.log；6 项模块独立构建复核：/private/tmp/keyrecord-uninstall-ci-fix-boundaries.log。未受本次拆分影响的其余场景复用上表结果。截图目录：/private/tmp/keyrecord-uninstall-ci-fix-qa；已检查英文卸载、中文恢复副本和合成固件状态截图。AX 测试实际按下独立确认按钮，验证确认前无副作用；合成固件测试实际生成临时文件并执行声明/证据动作。默认产品组成用例使用生产生命周期、存储、排空和清除对象，边界替换为内存 Keychain、假登录项、合成事件源和专用测试目录，验证保留及清除两种结果与失败停止。

失败/修复保留：首轮原生窗口缺少 AX 初始化，初始化后元素实际出现；系统 confirmationDialog 的 accessibilityPerformPress 返回 false，尽管动作完成，最终改用与既有危险流程一致的页面内确认，保留按下和结果断言。新确认按钮误用了仅作 AX ID 的 dialog.cancel/confirm，原有本地化审计报告两处缺项；改用有效文案并补齐双语。SDK 指出重复移除返回 job-not-found；首次引用错误域因 macOS 14 部署目标编译失败，改为一次显式状态读取及 macOS 15+ 错误域分支，注入错误用例确认没有吞掉签名/授权错误。首次 Swift 测试审批超时后重试通过。

## 自审与交付边界

本轮首次远端 [push CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38366227934) / [PR CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38366231717) 实际执行 666 项包测试，报告 3 处断言失败，均在原有 LifecycleBoundaryTests：Orchestrator 文件达到 256 行计数（要求小于 250），以及测试直接引用系统 SDK 符号，破坏唯一原生适配器约束。保留原检查，拆出 Foundation-only 登录移除助手；测试改从窄 DEBUG 工厂注入原生错误夹具，系统符号和调用仍只存在于唯一适配器。7 项原边界用例、14 项生命周期、3 项联网审计、6 项模块边界及 37 项 App 用例实际重跑通过；未降低错误级别或改变用户确认行为。失败日志：/private/tmp/keyrecord-uninstall-ci-failure.log。

| Lane | Exact source commit | Verdict | Evidence |
|---|---|---|---|
| 主会话代码自审 | e4cb2fc981665c12e3ab3ac5dbcaaac395cbb0a2 | 本增量通过 | 默认接线、顺序、票据/隐私、恢复副本保护、互斥与精确错误处理；git diff --check |
| 原生与离线执行 | e4cb2fc981665c12e3ab3ac5dbcaaac395cbb0a2 | 本增量通过 | 上表 107 项；原生截图与实际临时文件结果 |
| 主会话收口复查 | e4cb2fc981665c12e3ab3ac5dbcaaac395cbb0a2 | 本增量通过 | 不以源代码阅读替代 UI/执行；没有声称独立审查或真实后端合格 |

此前自动审批拦截是[前一增量](DEPLOYMENT_FIRMWARE_20261013.md)的历史状态，本批已在用户明确授权后完成入口。交付继续使用 [PR #25](https://github.com/fhtpku-Cli/KeyRecord/pull/25)，远端结果以 PR 当前提交的 checks 为准。

实际支持矩阵、官方导入器往返、Vial 设备读回、真实规则重载/效果/停用 p95、至少三款真实键盘、签名公证及 FR-P6 仍未取得。G3/G4、完整 FR-A4 和公开发布保持未完成；本批没有执行这些真实验证，也不请求重复确认。
