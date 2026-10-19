# Vial 6 官方基础键名离线兼容

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

状态日期：2026-10-14，Asia/Shanghai。从 [PR #33](https://github.com/fhtpku-Cli/KeyRecord/pull/33) 合并提交 `0bd3ea0f45f1e0b5d54fab628237466f4ea0bf21` 继续，在独立工作树及 `codex/vial-basic-keycodes` 分支实施。主目录及父任务工作树保持只读。

## 问题与范围

上一轮官方 `Keycode.serialize(0x1234)` 输出 `RSFT(KC_QUOTE)`，KeyRecord 却只认识 `KC_QUOT`，实际公开 API 驱动报 `unsupportedOutput`。本轮修复名称到原始键码的归一化；矩阵和编码器读回仍使用完整槽位集合、完整内容比较和原有加密事务。

覆盖官方 `KEYCODES_SPECIAL`、`KEYCODES_BASIC`（包括导航和数字键盘）及 `KEYCODES_ISO` 的 117 个标准名称和 68 个明确别名。包括标点长名、Escape、Insert、Delete、PageDown、PrintScreen、数字键盘、Menu、修饰键别名及 ISO/JIS/Korean 基础键码。这里比较的是固件数值，不声称某种主机输入法下的字符效果。

只补充静态 Swift 键名表，生产代码无 Python 依赖。未知/custom、宏、Tap Dance 和动态动作名称仍拒绝；原有完整 16 位 raw hex 路径保留。修饰键方向限制、嵌套深度、层范围及层入口/安全键码保护不变。该归一化修复不增加可自动生成的输出集合，也不开放生产设备支持。

## 官方来源与可复现夹具

使用本地官方 vial-gui 提交 [`aef8222a2d0429a183b2ed692d5f9efcfd383f08`](https://github.com/vial-kb/vial-gui/tree/aef8222a2d0429a183b2ed692d5f9efcfd383f08)，核对 `src/main/python/keycodes/keycodes_v6.py` 的数值及 `keycodes.py` 的名称、别名和实际 `serialize/deserialize`。静态夹具为 [`vial6-basic-keycodes.json`](../../evidence/phase4/fixtures/synthetic/vial6-basic-keycodes.json)；它记录该次实际源码执行结果，不构成新冻结 contract、hash、baseline 或 gate。

仓库根目录执行：

```bash
PYTHONPATH=/private/tmp/keyrecord-official-vial-python python3 Scripts/vial-official-roundtrip.py \
  --source /private/tmp/keyrecord-official-vial-gui \
  --generate /private/tmp/keyrecord-basic-original.vil --encoders --basic-keycodes \
  --definition /private/tmp/keyrecord-basic-definition.xz \
  --keycode-fixture evidence/phase4/fixtures/synthetic/vial6-basic-keycodes.json
swift run KeyRecordFirmwareIntegrationProbe /private/tmp/keyrecord-basic-original.vil \
  /private/tmp/keyrecord-basic-patched.vil /private/tmp/keyrecord-basic-definition.xz
PYTHONPATH=/private/tmp/keyrecord-official-vial-python python3 Scripts/vial-official-roundtrip.py \
  --source /private/tmp/keyrecord-official-vial-gui --encoders --basic-keycodes \
  --check /private/tmp/keyrecord-basic-patched.vil
```

`simpleeval` 仅供离线官方脚本执行。脚本未改写官方 `save_layout`、`restore_layout`、`reload_keymap` 方法；GUI、设备写入、宏/动态编辑和 `set_encoder` 仍为记录端口，不能据此声称真实 GUI 或设备恢复兼容。

## 实际验证

80 项不同的相关离线测试通过：2 项新键码回归、17 项适配、19 项固件操作、18 项设备读取、4 项隐私序列化、6 项模块边界，以及 14 项 App/原生场景。重复执行与参数变体不重复计数。未签名 arm64 App `build-for-testing` 成功。

| 场景 | 实际结果 | 证据 |
|---|---|---|
| 修复前回归 | 新增 2 项测试失败，官方名称/别名及 `RSFT(KC_QUOTE)` 等报 `unsupportedOutput` | `/private/tmp/keyrecord-basic-red.log` |
| 修复后名称与保护回归 | 117 个名称及 68 个别名逐项与官方源码结果一致；修饰、层范围、未知名和 raw hex 路径通过 | `/private/tmp/keyrecord-basic-core.log`、静态 JSON 夹具 |
| 完整事务与加密重开 | 标点、数字键盘及官方编码器名称完全一致为 verified；原始状态为 failed，矩阵或编码器单独变化为 externallyChanged；缺失观察拒绝 | core 日志 |
| 官方生成导出与公开 API | 20 份模拟报告、196 字节 XZ、14 个矩阵及 4 个编码器槽，完整比较与加密重开成功 | `/private/tmp/keyrecord-basic-official.log` |
| 官方方法往返 | 官方恢复/保存保持孔位、UID、编码器及不透明字段；官方 reload 发 2 条编码器查询且双方向数值不变 | 同一 official 日志 |
| 原生读回按钮 AXPress | `KC_KP_ENTER`、`KC_QUOTE`、`RSFT(KC_QUOTE)` 经 17 份模拟报告进入 Verified；主会话已查看截图 | `/private/tmp/keyrecord-basic-native.log`、`keyrecord-basic-qa/vial-basic-readback-en.png` |
| App 拒绝、隐私及取消 | 编码器外部变化如实记录；未知 USER00 保持 importClaimed 且无 verifiedAt；暂停后取消或清空隐私的迟到响应不能写证据；连接关闭一次 | 同一 native 日志 |
| 隐私与模块边界 | 4 项序列化及 6 项边界测试通过，默认工厂/空支持目录相关 App 场景通过 | `/private/tmp/keyrecord-basic-privacy.log`、core/native 日志 |

4 个触及 Swift 文件的 LSP 错误诊断为空。Python 语言服务器此前被用户拒绝安装，本轮未安装；脚本已实际执行。未修改已有 `observed` sendable、FlowTestComposition、BackendAnalysisView 及 AppIntents 警告。

主会话自审及 runtime audit 记录在 `/private/tmp/keyrecord-basic-review.md`，完成后绑定最终提交 SHA。CI/合并状态以 GitHub 实际检查为准。

## 证据边界

没有真实 HID open/send/枚举、捕获、用户配置/Keychain 修改、卸载、签名公证或发布。正式连接工厂 nil、生产支持目录为空；G2/G3/G4 和 v1 继续未合格。原生 IOHID 生命周期、复杂 KLE、非基础动作名称和动态子协议、VIA、真实设备和后台效果继续后置。无编号响应、同 UID 动态变化和非原子分块快照的限制仍在，真实验证需要静止配置。
