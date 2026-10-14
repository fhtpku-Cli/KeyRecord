# Vial 官方层点击名称离线兼容 — 2026-10-14

从 PR #35 合并提交 `1f9ce71e2bdf3ab9ae7db637148fedcf32058bcb` 继续；其主干 CI 38524001971 已 completed/success。

## 问题与修复

官方 `Keyboard.reload` 先调用 `recreate_keyboard_keycodes(self)`，再读键图。仅设置 `Keycode.protocol = 6` 时，层点击键可输出 raw hex；按设备层数初始化后，官方输出 `LT0(KC_C)` 到 `LT15(KC_C)`。修复前公开离线探针读实际初始化后的合成导出报 `unsupportedOutput`，键码回归有 1920 个失败断言。

Swift 增加 canonical `LTn(basic)` 解析，层范围仍为 0..<16，子键仍限制为原有基础名称集合及其别名。既有 `LT(layer,key)`、raw hex、修饰键方向和深度规则保留。名称归一化复用既有 `protectedEntry` 和 `layerEntry`：LT1 允许对应现有层的普通槽修补，入口本身不可自动或手动覆盖；LT0、缺失目的层和非法入口不能让另一层变成可达层。没有扩大自动输出允许集合，没有新增 hash、冻结 contract、baseline 或 gate。

后续自审发现解析失败的 `LT16(KC_C)`、`LT01(KC_C)`、`LT1(USER00)` 可能绕过原有手动入口保护。补充测试实际复现后，将现有保护覆盖到 LT 名称族，再解析有效值；非法语法不能借解析失败获得覆盖权限。原有 numeric LT 对非法子键的入口保护也保留。

官方离线脚本现在按夹具实际层数初始化键码表。新增 `--layer-tap-keycodes` 生成匹配的 16 层矩阵、稀疏编码器和独立原始字节。Python 仅是开发验证工具，不进入 App 运行时。

## 本轮实际证据

| 场景 | 结果 | 本机证据 |
| --- | --- | --- |
| 修复前键码回归及公开探针 | 1920 失败断言；探针 exit 2/unsupportedOutput | `/private/tmp/keyrecord-layer-tap-red.log`、`keyrecord-layer-tap-probe-red.log` |
| 非法名称入口回归 | 保护补丁前入口覆盖/错误类型断言失败，补丁后通过 | `/private/tmp/keyrecord-layer-tap-protection-red.log`、`keyrecord-layer-tap-core.log` |
| 包测试 | 6 键码、20 适配、19 固件事务、18 设备、6 产品边界；共 69 项通过 | `/private/tmp/keyrecord-layer-tap-core.log` |
| 隐私边界 | 4 项通过 | `/private/tmp/keyrecord-layer-tap-privacy.log` |
| App/原生 | 16 项通过；实际 AXPress 读回按钮后 Verified，时间已记录 | `/private/tmp/keyrecord-layer-tap-native.log`、`keyrecord-layer-tap-qa/vial-layer-tap-readback-en.png` |
| 官方方法及公开 API | 320 独立 big-endian 字节；42 模拟报告；196 字节 XZ；112 矩阵和 32 编码器方向槽完整比较；加密重开成功 | `/private/tmp/keyrecord-layer-tap-official.log` |
| 既有调用 | 初始化后基础/修饰夹具与仓库文件逐字一致；探针二、三参数及官方 restore/save/reload 通过 | `/private/tmp/keyrecord-layer-tap-legacy.log` |
| 未签名构建 | arm64 build-for-testing 成功 | `/private/tmp/keyrecord-layer-tap-build.log` |
| 诊断 | 4 个触及 Swift 文件 LSP 无错误；Python LSP 此前拒装，脚本已实际执行 | 主会话工具记录 |

总计 89 项不同相关包/App 测试通过，不能将官方脚本报告数计作测试数。完整比较覆盖 expected、原始未应用、矩阵外部变化和编码器单独变化，结果经过加密存储重开；未知动作、取消、隐私及迟到响应回归通过。CLI 帮助可用，缺失参数/互斥 generate-check 输入实际 exit 2。

官方源码版本 `aef8222a2d0429a183b2ed692d5f9efcfd383f08`。执行未改写的 `save_layout`、`restore_layout`、`reload_keymap` 方法及 `KleSerial`；编码器设置、宏等编辑仍由夹具端口记录，不证明真实 GUI 或设备恢复。

## 证据边界

正式连接工厂仍为 nil，生产支持目录仍为空。本轮没有真实 HID 打开、发送、枚举或捕获，没有真实用户配置、Keychain、卸载、签名公证或发布。构建保留已有 Keychain 弃用、Sendable、FlowTestComposition、BackendAnalysisView、ProductPersistence/Phase1FlowHostless 和 AppIntents 警告。真实版本与设备资格、复杂 KLE/动态动作/VIA GUI 和后台效果仍后置；G2/G3/G4 与 v1 未合格。模拟读回不证明非原子分块快照、无编号重复报告或同 UID 动态配置变化已解决。
