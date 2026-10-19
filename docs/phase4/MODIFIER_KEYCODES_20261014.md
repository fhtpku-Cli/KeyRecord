# Vial 6 普通组合修饰键离线兼容

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

状态日期：2026-10-14，Asia/Shanghai。从 [PR #34](https://github.com/fhtpku-Cli/KeyRecord/pull/34) 合并提交 `ad7c9c9c2ceef4f4f7c15c1d3a02fb67f2497571` 继续；其[主干 CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38466188256) 已成功。独立工作树及 `codex/vial-modifier-combinations` 分支实施，主目录和父工作树只读。

## 问题与实现

官方 `Keycode.serialize(0x0306)` 生成 `C_S(KC_C)`，现有 Swift 方言只能解析等价的嵌套形式，导致完整固件读回报 `unsupportedOutput`。本轮补齐 10 个普通组合名称：C_S、LCA、LSA、MEH、LCG、SGUI、LAG、LCAG、HYPR、RCG，以及 14 个实际有效的组合/单修饰别名，包括 LSG、SCMD、SWIN 和 C/S/A/G。生产改动仅为现有静态 Swift 名称到数值表。

官方源码来自 vial-gui [`aef8222a2d0429a183b2ed692d5f9efcfd383f08`](https://github.com/vial-kb/vial-gui/tree/aef8222a2d0429a183b2ed692d5f9efcfd383f08)，实际执行 `keycodes_v6.py`、`keycodes.py`、`any_keycode.py` 的 serialize/deserialize。夹具记录 18 个普通名称（含原有 8 个单修饰）和 14 个工作别名，并与 115 个非无键/透明基础值交叉验证。

`LCS` 虽在静态表声明，但实际 `deserialize(..., reraise=True)` 抛 FunctionNotDefined，默认返回 0，故继续拒绝。RSA/RCS 实际能解码但序列化为 raw hex，本轮不增加这些名称。现有 16 位 raw hex 通道保持原样；Tap Dance、Mod Tap、OSM、未知/custom、宏/动态名称仍不在本轮命名范围。左右修饰混用、嵌套深度、无键/透明子键、层范围和层/安全入口保护均保留。自动输出允许集合、正式工厂 nil、空生产支持目录不变。

## 独立官方字节与完整闭环

离线官方脚本新增 `--modifier-keycodes`、`--modifier-fixture` 与 `--raw-keycodes`。最后一项用官方 deserialize 生成 big-endian 矩阵和编码器字节；公开 Swift 探针接收可选第四参数，将这些独立字节放入模拟报告。矩阵按层/行/列排序，编码器按层/索引/方向排序。这是本地测试输入，不是新增冻结 contract、hash、baseline 或生产 gate。

```bash
PYTHONPATH=/private/tmp/keyrecord-official-vial-python python3 Scripts/vial-official-roundtrip.py \
  --source /private/tmp/keyrecord-official-vial-gui --generate /private/tmp/keyrecord-modifiers-original.vil \
  --encoders --modifier-keycodes --definition /private/tmp/keyrecord-modifiers-definition.xz \
  --modifier-fixture evidence/phase4/fixtures/synthetic/vial6-modifier-keycodes.json \
  --raw-keycodes /private/tmp/keyrecord-modifiers-raw.bin
swift run KeyRecordFirmwareIntegrationProbe /private/tmp/keyrecord-modifiers-original.vil \
  /private/tmp/keyrecord-modifiers-patched.vil /private/tmp/keyrecord-modifiers-definition.xz \
  /private/tmp/keyrecord-modifiers-raw.bin
PYTHONPATH=/private/tmp/keyrecord-official-vial-python python3 Scripts/vial-official-roundtrip.py \
  --source /private/tmp/keyrecord-official-vial-gui --check /private/tmp/keyrecord-modifiers-patched.vil \
  --encoders --modifier-keycodes
```

官方 save_layout、restore_layout、reload_keymap 方法未改写。GUI/HID、宏/动态编辑和 set_encoder 仍是离线记录端口，不能证明真实恢复兼容。首次新增四参数探针误选旧版本轴而拒绝 unknownCompatibility；修正为有独立定义时沿用其 schema 后，完整闭环成功，产品版本拒绝规则没有变化。

## 实际验证与自审

84 项不同的直接相关场景通过：4 项键码（其中新增 2 项）、18 项适配（新增 1 项）、19 项固件操作、18 项设备读取、4 项隐私序列化、6 项边界和 15 项 App/原生（新增 1 项）。变体与重复执行不重复计数。未签名 arm64 App build-for-testing 成功。

| 场景 | 观察结果 | 本地证据 |
|---|---|---|
| 修复前回归 | 1 项新增名称回归失败，2784 个 unsupportedOutput 断言；父轮另有 9 个公开 API 失败 | `/private/tmp/keyrecord-modifiers-red.log`、`keyrecord-modifier-discovery.log` |
| 名称与保护 | 18 普通名称、14 别名与官方值一致，组合嵌套和左右方向/深度/未知/层/安全入口规则通过 | `keyrecord-modifiers-core.log`、静态 JSON 夹具 |
| 完整矩阵/编码器事务 | 正确为 verified、原始状态为 failed、矩阵或编码器单独变化为 externallyChanged；加密重开保持结果，缺失观察拒绝 | 同一 core 日志 |
| 官方字节与公开 API | 40 独立原始字节、20 份模拟报告、196 字节 XZ、14 矩阵及 4 编码器槽；完整比较与加密重开成功 | `keyrecord-modifiers-official.log` |
| 官方方法往返 | 孔位、UID、编码器及不透明字段保持，reload 双方向数值不变 | 同一 official 日志 |
| 原生 AXPress | C_S(KC_KP_ENTER)、SCMD(KC_QUOTE)、RCG(KC_QUOTE) 经 17 份报告进入 Verified；主会话已看截图 | `keyrecord-modifiers-native.log`、`keyrecord-modifiers-qa/vial-modifiers-readback-en.png` |
| App 外部变更/拒绝/取消 | 编码器单独变化仍外部变更；USER00 保持 importClaimed 且无 verifiedAt；隐私或取消后迟到报告不写证据，连接关闭一次 | 同一 native 日志 |

日志位于 `/private/tmp`。5 个触及 Swift 文件 LSP 错误为空；Python 语言服务器此前拒绝安装，未安装，脚本已实际执行。原有 Keychain 弃用、FlowTestComposition、ProductComposition Sendable、ProductPersistence、BackendAnalysisView 及 AppIntents 警告保留。主会话自审记录 `/private/tmp/keyrecord-modifiers-review.md`，CI/合并以 GitHub 实际状态为准。

## 仍后置的资格

没有真实 HID open/send/枚举、捕获、真实用户配置/Keychain、卸载、签名公证或发布动作。离线模拟、构建和 CI 不证明设备、后台效果或 Release 资格；G2/G3/G4 与 v1 继续未合格。复杂 KLE、Mod Tap/其他动作与动态子协议、VIA 和 IOHID 真实生命周期仍后置。无编号重复报告、同 UID 动态变化和非原子分块快照限制保留，真实验证需要静止配置。
