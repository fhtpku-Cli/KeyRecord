# KeyRecord

KeyRecord 是开发中的原生 macOS 菜单栏应用，用于本地键盘使用聚合统计、可解释的改键建议及受约束的配置工作流，不保存输入文本或逐事件序列。源码使用 Swift 6；最低编译目标 macOS 14+，不等于全部目标系统已获运行资格。

**截至 2026-10-20，已按用户指示恢复完整 v1 工程，见[执行计划](docs/V1_DEVELOPMENT_PLAN_20261020.md)。** 已完成限定 Apple Silicon 采集 MVP、Phase 2 A/B 离线工程、Karabiner 事务与行为测试流程、VIA 基础键文件编辑、Vial 只读协议/定义快照，以及完整密码备份与空资料库恢复。完整 Phase 3/4、真实后端支持和公开发行仍未合格。

先看[当前状态](docs/PROJECT_STATUS.md)、[路线图](docs/ROADMAP.md)、[逐项需求核对](docs/V1_REQUIREMENT_AUDIT_20261020.md)和[全部文档索引](docs/STATUS_INDEX.md)。本轮增加来源一致性、旋转/布局选项、普通配置导出、命名、菜单快捷键参考、更新检查与发布工具；对应 PR 和最终提交 CI 见执行计划。

## 用户工作流与限制

- 统计和建议使用已有聚合；推荐到 Karabiner 草稿保留组合快捷键与应用范围。
- VIA：主动导出最新配置，在 KeyRecord 选实际层/位置与支持的基础键，预览导出，再手动导回 VIA。文件编辑不依赖浏览器实例绑定，也不证明实际键盘效果；当前不生成组合快捷键、应用专属规则或高级动作。
- Vial：已接入显式设备选择及只读协议工厂，但生产设备支持目录为空，未知设备不会因此放行。定义/键码读取及离线回放不等于设备合格。
- 物理来源可展示文件、系统属性、型号及布局快照参考；完整证据链不足时继续逻辑比较。一次型号匹配或读回不是实时物理映射。
- 密码备份包含全部已提交保存对象；恢复只接受空资料库，不覆盖既有数据，恢复后不自动采集或应用映射。真实 Keychain 恢复与卸载后置，删除前复核保留。

## 构建与测试

<a id="build-and-test"></a>

需要 macOS、完整 Xcode 和 Swift 6.2 或更新版本（源码使用 `isolated deinit`）。从干净检出运行：

```sh
Scripts/verify-local.sh
```

脚本顺序执行全部 SwiftPM 测试、发布工具模拟测试、捕获工具离线回归、SwiftPM Release 构建、未签名 Universal Release App 构建、原生架构 Debug `build-for-testing`，检查发布源码/包结构/二进制网络边界，默认最后执行 hostless App XCTest。失败即停止，不能据前一步成功推断后续完成。完整原生测试需要合适的图形会话，阻塞、跳过和失败不算通过。

| 命令 | 与默认模式的区别 |
|---|---|
| `Scripts/verify-local.sh --build-only` | 仍执行包测试及构建，只跳过 App XCTest 执行 |
| `Scripts/verify-local.sh --firmware-app-tests` | 执行固件/映射、导入、更新确认、发布边界与生产组合的原生离线子集，不执行整个 App 测试包 |

**当前 [macOS CI](.github/workflows/macos.yml) 使用 `--firmware-app-tests`，不是 `--build-only`。** CI 先取得工作流指定版本的官方 VIA/Vial 方法及依赖，执行 `Scripts/verify-firmware-oracles.py`，再运行包测试、构建和原生离线子集。工具链配置为 Xcode 26.3、`macos-15`，以实际工作流和对应提交日志为准。首次下载依赖需要网络，验证使用合成输入，不连接真实键盘。

日志与产物在 `.build/verification/run.*`，原生截图位于对应 `qa/`。不要并行使用同一个 SwiftPM 构建目录。测试数量属于特定提交，不能用旧数量或旧 CI 代表当前代码，也不能把构建成功当 XCTest 已执行。

## 真实验证与发布边界

更新检查只向固定 GitHub Releases 地址发送空 GET，默认每周一次；用户确认后打开官方页面手动下载安装，不上传统计或配置。正式名称 KeyRecord，自有代码采用 [Apache-2.0](LICENSE)，[第三方声明](THIRD_PARTY_NOTICES.md)随包提供。[发布工具](docs/RELEASE_PREPARATION_20261020.md)已有模拟验证，尚未执行真实签名、公证或发布。

已批准 Phase 1 MVP 的实测限定于原候选、原生 arm64 macOS 27.0 build `26A428`；开发签名的 Release 构建不是公证后的公开发行。当前锁屏来源可用于原生 arm64 macOS 27 及以后版本，锁屏状态为锁定或未知时停止采集，不据此声称后续系统均已实测。

真实 Karabiner 效果/重载、VIA GUI 导入、Vial HID、密码备份的 Keychain 恢复、完整卸载及发布验证尚未完成。新实机轮次须明确构建、身份、隔离资料库/Keychain 范围、动作与时间，并取得适用授权。普通构建、CI 和旧试验说明不授权操作日常配置、TCC、真实设备或删除用户数据。

锁屏或崩溃可能丢失上次成功持久化后的统计；一秒保存节奏不是数据丢失上限保证。详见 [Phase 1 验收](docs/PHASE1_ACCEPTANCE.md)和[实机验证说明](docs/LIVE_VERIFICATION_NOTES.md)。

## 仓库结构

- `Sources/`、`Tests/`：采集、存储、分析、配置解析、映射和设备读取模块及测试。
- `App/`、`KeyRecord.xcodeproj`：原生产品、App XCTest 与 XCUITest。
- `Scripts/`：开发验证和既有专项验证工具。
- `docs/`：现行需求、架构、状态，以及明确标注的历史记录。
- `Spikes/`、`evidence/`、已跟踪的 `.omo/` 文档：历史实验、证据与计划；不重写原始结论，不把其中命令视为当前执行授权。
