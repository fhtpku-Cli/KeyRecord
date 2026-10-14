# Vial TO 精确名称编码与回读修复

日期：2026-10-15。范围：离线 Vial 6 方言、修补可达层和既有回读比较。

## 已复现的问题

官方 `vial-gui` 提交 `aef8222a2d0429a183b2ed692d5f9efcfd383f08` 在初始化 32 层键盘后，实际序列化/反序列化得到 `TO(0)` 至 `TO(31)` 对应 `0x5200` 至 `0x521f`。原 Swift 方言却以 `0x5210` 为起点且只接受 16 层。

完整公共事务驱动使用 32 层、64 个矩阵槽、内存密钥、临时加密存储和合成导出，实际执行 retain/export/claimImport/confirmVialReadback：

| 原文件名称 | 观测原始值 | 修复前 | 修复后 |
| --- | --- | --- | --- |
| `TO(1)` | `0x5201` | externallyChanged | verified |
| `TO(1)` | `0x5211`（官方 TO17） | verified | externallyChanged |

前后运行使用相同驱动源文件。证据：`/private/tmp/keyrecord-to-public-before.log`、`/private/tmp/keyrecord-to-public-after.log`。

## 最小修复

产品只修改 `VialKeycodeDialect.swift`：TO 基址改为 `0x5200`，范围修正为 32 层，名称必须与十进制规范形式完全一致。原始值 `0x5211` 现在映射到 TO17。无法解码的 `TO(` 名称不再原样交给可达层解析，防止 `TO(01)`、`TO(+1)` 或逗号表达式被当成合法层入口。

官方精确名称和表达式路径有差异：`TO(1)` 为 `0x5201`，` TO(1)` 为 `0x5211`。本轮只接受精确名称，不开放表达式或空白变体。已有入口不可覆盖、TO 不授权自动层、普通输出许可及完整矩阵/旋钮比较规则均保留。手动修补仅能到达原始值实际指向且文档中存在的层。VIA 和其他方言没有改动。

## 实际执行的验证

- 修改产品源码之前运行 4 项选定测试，出现 12 个失败断言，涵盖编码、可达层、未支持的高层名称与非规范名称接受。日志：`/private/tmp/keyrecord-to-red.log`。
- 修复后 84 项映射测试、18 项设备读取测试全部通过。新增三项测试使用官方生成的 32 名称夹具，覆盖所有目标层、保护和输出拒绝、双方向旋钮、完整矩阵、原图未导入、错误目标和加密记录重开。日志：`/private/tmp/keyrecord-to-tests.log`。
- `Scripts/vial-official-roundtrip.py --to-keycodes --to-fixture ... --encoders` 实际生成官方导出、独立 XZ 定义及 640 字节回读数据；官方名称夹具保存在 `evidence/phase4/fixtures/synthetic/vial6-to-keycodes.json`。
- 公共 `KeyRecordFirmwareIntegrationProbe` 使用这些独立字节，实际交换 67 次模拟报告，解压 196 字节定义，比较 224 个矩阵槽和 64 个旋钮方向槽，得到 verified 并重开加密记录。官方原始 restore/save/reload 方法随后接受修补文件，保留空位、UID 和不透明字段。日志：`/private/tmp/keyrecord-to-public.log`、`/private/tmp/keyrecord-to-official.log`、`/private/tmp/keyrecord-to-official-check.log`。
- 未签名 arm64 `build-for-testing` 成功；65 项 `KarabinerMappingFlowTests` 原生测试通过，包含真实 AXPress、状态日期、取消和隐私迟到响应。原生沿用已有夹具，不将其描述为 TO 专项原生验证。日志：`/private/tmp/keyrecord-to-xcode.log`、`/private/tmp/keyrecord-to-native.log`；截图：`/private/tmp/keyrecord-to-qa/vial-basic-readback-en.png`。
- 三个触及 Swift 文件的 LSP 无错误，`git diff --check` 通过。Python LSP 沿用此前不安装的选择，以脚本实际执行验证。构建保留既有警告，没有添加警告抑制。

复现官方路径：

```bash
PYTHONPATH=/private/tmp/keyrecord-official-vial-python python3 Scripts/vial-official-roundtrip.py \
  --source /private/tmp/keyrecord-official-vial-gui --to-keycodes --encoders \
  --to-fixture /private/tmp/to-keys.json --generate /private/tmp/to-original.vil \
  --definition /private/tmp/to-definition.xz --raw-keycodes /private/tmp/to-raw.bin
swift run KeyRecordFirmwareIntegrationProbe /private/tmp/to-original.vil /private/tmp/to-patched.vil \
  /private/tmp/to-definition.xz /private/tmp/to-raw.bin
PYTHONPATH=/private/tmp/keyrecord-official-vial-python python3 Scripts/vial-official-roundtrip.py \
  --source /private/tmp/keyrecord-official-vial-gui --to-keycodes --encoders --check /private/tmp/to-patched.vil
```

## 证据边界

没有真实 HID 打开、枚举、发送、捕获，没有操作真实用户配置、Keychain、卸载、签名、公证或发布。生产支持目录仍为空，默认连接 factory 仍为 nil。合成夹具、官方源码方法、模拟端点、构建和 CI 不建立真实设备、后台或 Release 资格。G2/G3/G4 与完整 v1 仍未合格；同 UID 动态变化、非原子分块快照和无编号重复报告仍需静止配置下真实验证。
