# Vial 静态 modifier-tap 名称离线兼容 — 2026-10-14

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

从 PR #36 合并提交 `18f97d9f387458196662512abb45ad09ab4eee9c` 继续；其主干 CI 38527410298 已 completed/success。

## 问题与范围

官方 Vial 6 按设备初始化后，将静态 modifier-tap 值输出为 `LSFT_T(KC_C)` 等名称。修复前公开离线探针对实际官方合成导出返回 exit 2 / `unsupportedOutput`；新增键码回归有 6845 个失败断言。源码读取覆盖官方 `keycodes.py`、`keycodes_v6.py` 和 `any_keycode.functions`，并实际使用 `recreate_keyboard_keycodes`、`serialize`、`deserialize(..., reraise=True)` 验证。

Swift 仅加入 19 个 canonical 静态 modifier-tap 名称和 18 个实际有效别名，子键限制为既有基础名称及其别名。官方生成夹具覆盖左/右单修饰键、组合及 ALL_T；HYPR_T 是 ALL_T 的有效别名，因此将旧的 HYPR_T(KC_C) 拒绝预期更新为兼容证明，同时保留 HYPR_T(MO(1)) 等非基础子键拒绝测试。没有开放数字 `MT(mod,key)`、递归/嵌套/动态动作或新的自动修补输出。

静态声明的 LCS_T 实际未注册，reraise=True 抛 FunctionNotDefined；RSA_T/RCS_T 可被官方反序列化，但官方保存输出 raw hex，不扩展这些名称。实际运行排除了 KC_SFTENT 等同 RSFT_T(KC_ENTER) 的假设：它是独立 `0x7c1e` 动作，仍拒绝。raw hex 仍按现有规则保留。

## 实际验证

| 场景 | 结果 | 本机证据 |
| --- | --- | --- |
| 修复前复现 | 8 个键码场景、6845 失败断言；旧公开探针 unsupportedOutput | `/private/tmp/keyrecord-modtap-red.log`、`keyrecord-modtap-probe-red.log` |
| 包测试 | 8 键码、22 适配、19 固件事务、18 设备、4 隐私、6 产品边界，共 77 项零失败 | `/private/tmp/keyrecord-modtap-core.log` |
| 原生 App | 20 项零失败；实际 AXPress 读回按钮后 Verified/日期；17 报告、close once | `/private/tmp/keyrecord-modtap-native.log`、`keyrecord-modtap-qa/vial-modifier-tap-readback-en.png` |
| 独立官方字节 | 40 big-endian 字节、20 模拟报告、196 字节 XZ；14 矩阵及 4 编码器方向槽完整比较，加密重开成功 | `/private/tmp/keyrecord-modtap-generation.log`、`keyrecord-modtap-probe.log` |
| 全部名称/别名公开 API | 19 canonical + 18 alias 逐个用官方独立字节走完整导出、读回、加密重开；9 个不支持动作被拒绝 | `/private/tmp/keyrecord-modtap-public-qa.py`、`keyrecord-modtap-public-qa.log` |
| 官方恢复及读回方法 | 实际 restore_layout/save_layout/reload_keymap 执行通过；稀疏编码器双方向保留 | `/private/tmp/keyrecord-modtap-official-restore.log` |
| 既有调用 | 原二、三参数探针通过；117 基础名称/68 别名及 18 普通修饰名称/14 别名生成夹具与仓库逐字一致 | `/private/tmp/keyrecord-modtap-legacy.log`、`keyrecord-modtap-legacy-probe.log` |
| CLI 边界 | 探针/官方脚本帮助成功，探针缺参和脚本 generate/check 互斥输入 exit 2 | `/private/tmp/keyrecord-modtap-public-qa.log`、`keyrecord-modtap-help.log`、`keyrecord-modtap-invalid.log` |
| 构建与诊断 | 未签名 arm64 build-for-testing 成功；4 个触及 Swift 文件 LSP 无错误 | `/private/tmp/keyrecord-modtap-build.log`、主会话诊断记录 |

共 97 项不同包/App 场景通过，官方名称遍历和报告数不计为额外 XCTest 数。适配回归覆盖 expected、原始未应用、矩阵外部变化、编码器单独外部变化及加密重开；原生回归进一步验证 modifier-tap 编码器单独变化、未知 USER00 子键不能生成 verifiedAt、取消/隐私切换后的迟到响应不写入证据、连接只关闭一次。

自动输出允许集合仍由原有 standard-output 检查限定。新增回归证明，即使合成支持目录列入 modifier-tap，自动输出仍拒绝；modifier-tap 或非法嵌套动作不能让另一层可达。既有 MO、LT、非法 LT 子键及启动/清除入口自动和手动保护保留。没有新增 hash、冻结 contract、baseline 或 gate。

## 证据边界

官方源码 SHA `aef8222a2d0429a183b2ed692d5f9efcfd383f08`。Python 验证工具执行未改写的官方保存、恢复、读回方法及 KleSerial；编码器设置及宏等编辑仍由夹具端口记录，不证明实际 GUI 恢复或设备写入。Python/JSON LSP 安装此前被用户拒绝，本轮未安装；脚本已实际执行，夹具逐字比较通过。

生产支持目录保持空，连接工厂保持 nil。没有真实 HID 打开/发送/枚举/捕获、用户配置/Keychain/卸载、签名公证或发布。本轮未建立真实设备、后台效果或 Release 资格；G2/G3/G4 和 v1 继续未合格。非原子分块快照、无编号重复报告及同 UID 动态配置变化等真实验证限制保留。

构建保留既有 Keychain 弃用、FlowTestComposition/ProductComposition Sendable、BackendAnalysisView、ProductPersistence、KarabinerMappingFlowTests 的 observed 捕获及 AppIntents 警告；改动未弱化测试或抑制诊断。
