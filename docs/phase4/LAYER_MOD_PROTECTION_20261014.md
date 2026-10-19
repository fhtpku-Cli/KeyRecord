# Vial LM 入口保护补齐（2026-10-14）

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

## 结论与范围

修复 Vial 6 原始 LM 层修饰动作可被手动覆盖的问题。`FirmwareDocument.patch(automatic: false)` 曾允许把 `0x5000`、`0x5021`、`0x51ff`、`LM(1,MOD_LCTL)`、未知参数及前导空白形式替换为 `KC_C`。现有 `protectedEntry` 在解析前识别 LM 名族，并补齐 `0x5000...0x51ff`；拒绝结果为 `protectedEntry`。

生产改动仅两行，不新增 LM 表达式解析、层可达性或输出授权，不引入额外 hash、contract、baseline 或 gate。普通 raw 的手动替换行为保留。生产支持目录仍为空，默认设备连接 factory 仍为 nil。

## 官方来源及执行

官方 vial-gui 源提交：`aef8222a2d0429a183b2ed692d5f9efcfd383f08`。Vial 6 的 `QK_LAYER_MOD=0x5000`、`QMK_LM_SHIFT=5`、`QMK_LM_MASK=0x1f`。实际调用官方反序列化及序列化，16 层 × 32 掩码全部 512 个值恰好覆盖 `0x5000...0x51ff`，canonical 仍为十六进制。官方表达式可掩码截断越界参数，因此本产品不据此开放表达式。

`Scripts/vial-official-roundtrip.py --layer-mod-keycodes` 提供可重复的官方方法执行：检查全部 512 种组合，生成 16 层矩阵、稀疏双向编码器及独立 big-endian 数据；保留已有官方 `save_layout`、`restore_layout`、`reload_keymap` 原始方法。参数示例：

```sh
PYTHONPATH=/private/tmp/keyrecord-official-vial-python python3 Scripts/vial-official-roundtrip.py \
  --source /private/tmp/keyrecord-official-vial-gui --encoders --layer-mod-keycodes \
  --generate /private/tmp/keyrecord-lm-original.vil \
  --definition /private/tmp/keyrecord-lm-definition.xz --raw-keycodes /private/tmp/keyrecord-lm-raw.bin
```

## 本轮实际验证

- Failing-first：两项新回归在旧产品代码执行，1052 个失败断言，来自 512 raw + 14 名称各自的自动错误类别及手动覆盖缺口；相邻动作检查通过。相同回归在修复后通过。
- 全部映射包 80 项、设备读取模拟 18 项、产品边界 6 项，共 104 项通过。检查原入口保护、不可达层拒绝、LM 作为新输出仍被拒绝，以及相邻 LT/PDF/boot/static 保护与普通 raw 手动替换。
- 独立 Swift 公共 API 驱动重跑六个原始漏洞输入，全部返回 `protectedEntry`；`0x52a1`、`0x5fff`、`KC_A` 手动替换成功。
- 官方数据闭环：320 独立字节、196 字节 XZ 定义、42 个模拟 HID 报告，112 个矩阵槽与 32 个编码器方向槽完整比较，得到 verified 并成功重开加密记录；官方 restore/save/reload 再次通过。
- 独立编码器 raw 单独变化使公共探针退出 2，未获得 verified；LM 编码器表达式与合法独立 raw 比较返回 `unsupportedOutput`。未削弱或修改产品比较逻辑。
- 未签名 arm64 `build-for-testing` 成功；原生 `KarabinerMappingFlowTests` 65 项通过，含真实 AXPress、verified 状态、加密重开、编码器变化、取消及隐私迟到响应回归。原生回归沿用已有夹具，不是 LM 物理效果证明。
- 脚本与探针 help 退出 0；缺参、generate/check 冲突按预期退出 2。
- 两个触及的工程 Swift 文件 LSP 无错误。Python LSP 未安装，沿用用户不安装的决定，以脚本实际执行验证。独立临时 Swift 包实际编译运行通过；其编辑器仍因外置 scratch 模块路径报告找不到依赖，不计为该临时包 LSP 通过。

证据保存在 `/private/tmp/keyrecord-lm-{red,tests,official,public,probe,cli-qa,xcode,native}.log`，原生截图在 `/private/tmp/keyrecord-lm-qa/`。主会话最终自审与精确提交记录在 `/private/tmp/keyrecord-lm-review.md`。

## 资格边界

以上均为离线合成夹具、官方源码方法、模拟设备与未签名构建证据。没有真实 HID open/send/枚举/捕获，没有操作真实用户配置或 Keychain，没有签名、公证或发布。G2/G3/G4 与 v1 仍未合格；真实设备、同 UID 动态变化、非原子分块快照及无编号重复报告仍需静止配置条件下的实际验证。CI 不运行 App XCTest，原生测试证据来自本轮本机执行。
