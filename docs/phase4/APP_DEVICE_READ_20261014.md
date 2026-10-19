# 独立设备读回接入 App

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

状态日期：2026-10-14，Asia/Shanghai。起点为 [PR #31](https://github.com/fhtpku-Cli/KeyRecord/pull/31) 合并提交 `c9a9d855e68008c1e821a45ac624bdb4964ea295`，其[主干 CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38437650933) 已成功。本批在本任务受管隔离工作树及 `codex/app-device-read-session` 实施；主目录的历史改动保持只读。

## 行为与所有权

此前 App 的读回按钮只能接收上层观察值或矩阵适配器，独立设备定义会话尚未进入 App 路径。本批新增可选的同步连接工厂；只有批次兼容、隐私允许、原始副本解密成功且操作仍有效时才调用。连接工厂按当前选择创建新连接；重选或移除选择通过重新配置工厂，立即清空旧票据并关闭活动连接。默认产品组成仍未提供工厂。

`VialDeviceReadConnection` 持有一条 `VialHIDTransport` 和一份 `VialDeviceReadSession`，仅供一次读回操作所有。实际路径为加密原始副本 → VIA/Vial 身份和分页 XZ 定义 → 独立 VID/PID、行列与每层占用坐标 → 完整键图 → 既有完整比对和加密证据事务。没有把文件本身当作独立定义，也没有用上层模拟观察值替代报告集成。

成功、解析/授权拒绝、传输故障和任务取消均关闭连接。App 隐私清空与重新配置会同步终止传输的待处理交换；原生端口自身仍按串行队列排空并释放缓冲，不宣称关闭调用已经完成系统取消。显式 `cancelVialReadback` 使当前请求失效；旧异常、完成及清理不能覆盖后续请求的状态或关闭它的连接。下一次验证重新调用工厂，不自动重试、重选或重开设备。既有隐私代次检查仍覆盖每份报告和发布，既有事务边界保持原样。

实际 App 场景暴露了显式关闭后传输析构重复调用端口关闭的问题。本批修正析构仅在尚未关闭时关闭；相同场景修复前失败、修复后通过，并加入包级生命周期回归。既有事务的 `verifiedAt` 表示观察证据时间，失败或外部变更也记录时间；验证成功必须同时看 `.verified` 状态，未修改既有语义。

没有新增 hash、冻结 contract、baseline 或工程 gate，没有移除/削弱既有支持目录、隐私、加密原始副本、完整键图比对和事务措施。Xcode App/测试目标仅加入已有设备读取库的链接关系，不把 IOKit 加入分析、存储或映射模块。

## 本轮实际验证

66 项不同的相关测试通过：15 项设备读取、13 项协议适配、19 项固件操作、4 项隐私、6 项模块边界和 9 项 App/原生测试。变体与重复执行不额外计数。

| 场景 | 实际结果 | 产物 |
|---|---|---|
| 原生读回按钮 AXPress | 16 次模拟 HID 报告，176 字节 XZ 独立定义、两处占用位置及完整键图比对后显示 Verified | `/private/tmp/keyrecord-app-device-native.log`、`keyrecord-app-device-qa/vial-protocol-readback-en.png` |
| 独立 VID/PID 和相同键数但占用坐标错误 | 均在键图查询前拒绝，未写验证结果，连接关闭一次 | 同一 native 日志 |
| 键图不一致 | 既有事务记录 externallyChanged，加密日志重开保持状态 | 同一 native 日志 |
| 任务取消、设备断开、隐私锁定/解锁、选择更换、显式取消 | 在定义页或键图报告暂停后执行；停止后无新增报告、无验证结果；迟到输入无效 | 同一 native 日志 |
| 并发按钮、取消后重新验证 | 活动操作不多开连接；下一次使用新连接，旧完成不覆盖新 Verified；加密结果重开一致 | 同一 native 日志 |
| 已取消任务和未知支持目录 | 工厂未调用、零报告；默认 nil 和旧观察值注入场景仍通过 | 同一 native 日志 |
| 关闭/析构回归、协议/事务/隐私/边界 | 57 项包测试零失败 | `/private/tmp/keyrecord-app-device-core.log` |
| 未签名 arm64 App build-for-testing | 成功；保留已有 observed sendable 捕获及无 AppIntents 元数据警告 | `/private/tmp/keyrecord-app-device-build.log` |
| 修复前 App 场景 | 关闭计数为 2 的断言实际失败；修复后同场景为 1 | `/private/tmp/keyrecord-app-device-native-red.log`、最终 native 日志 |

包测试命令：

```sh
swift test --scratch-path /private/tmp/keyrecord-app-device-swift --filter 'VialDeviceReadTests|VialReadbackAdapterTests|FirmwareOperationTests|ProductBoundaryTests|PrivacyBoundaryTests'
```

App 测试通过清除继承捕获/调试开关的 `env -i ... xcrun xctest -XCTest ... KeyRecordAppTests.xctest` 执行。所有文件、密钥和 HID 端口均为合成夹具/专用临时存储；执行真实模型、原生 SwiftUI 按钮、系统 XZ 解码及加密存储，不打开真实 HID。主会话已查看原生截图。LSP 对 App 模型、设备定义/传输及 App 测试报告零错误；实际 Swift/Xcode 编译通过。

主会话按 review-work/debugging 方法自审连接所有权、报告时序、隐私、请求失效、旧完成、支持目录、既有事务及模块依赖。最终提交对应的自审和运行审计记录为 `/private/tmp/keyrecord-app-device-review.md`；PR 和主干 CI 状态以实际 GitHub 检查为准。

## 剩余证据边界

正式连接工厂仍 nil、生产支持目录仍为空，没有启用设备选择 UI或后台连接。没有真实 HID open/send/枚举、捕获、日常配置修改、卸载、Keychain/用户数据删除、签名/公证或发布。模拟报告和 App 截图均不证明真实键盘效果或 Release 资格。

原生 IOHID 权限/报告/取消缓冲生命周期、真实版本/键码矩阵、复杂 KLE/编码器/完整动态协议、VIA 设备及官方 GUI/后台效果继续后置。无编号重复响应、同 UID 动态变化和分块键图非原子快照限制沿用[上一轮记录](HID_DEFINITION_20261014.md)，真实验证需静止配置。G2/G3/G4 和完整 v1 未合格。
