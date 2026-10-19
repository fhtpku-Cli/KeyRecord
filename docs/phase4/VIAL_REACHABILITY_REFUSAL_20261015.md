# Vial 6 解析失败不得授予层访问

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

## 问题与实际复现

基于 main `04a5d1714de652994b461af104666c902758d07d`，合成 17 层 Vial 文档：第 0 层包含待测入口，第 1 层包含 `MO(2)`，各层均有一个空槽。使用显式测试支持目录调用公开 `FirmwareDocument.patch`。

| 原始入口 | KeyRecord 键码解析 | 修复前实际 patch | 修复后 |
| --- | --- | --- | --- |
| `MO(1,2)` | 拒绝 | 自动/手动放行层 1，手动放行层 2 | 均报 `unreachableLayer` |
| `LT(1,USER00)`、`LT(1,MO(0))` | 拒绝 | 自动/手动放行层 1，手动放行层 2 | 均报 `unreachableLayer` |
| `LT(16,KC_A)` | 拒绝 | 自动/手动放行层 16 | 均报 `unreachableLayer` |
| `TG/DF/OSL/TT(1,2)` | 拒绝 | 手动放行层 1 和层 2 | 均报 `unreachableLayer` |
| `MO(1)`、`LT1(KC_A)` | 成功 | 自动/手动放行层 1，手动放行层 2 | 保持正常 |

根因：`VialKeycodeDialect.layerEntry` 对非 TO 的解析失败返回原始字符串；通用可达性遍历只读取括号内第一个逗号字段，重新接纳了方言明确拒绝的表达式。该结果进入预览、准备和导出。新增测试在旧产品代码上实际写出了 545 字节的临时导出文件，并把加密记录由 `draft` 推进为 `awaitingUserImport`。

## 最小修复与覆盖

解析失败统一返回空入口，让现有可达性遍历跳过该值。成功解析的 MO/LT 和手动层动作保持原语义；其他位置的未知内容仍按原字节保留，独立有效入口仍可通行。修改不扩充键码支持，不新增 hash、冻结 contract、baseline 或 gate。

`VialLayerReachabilityTests` 覆盖：

- 14 种拒绝表达式、自动/手动、直接/间接/高层目标；非法入口自身仍不可覆盖，普通层 0 空槽仍可修改。
- 合法名称、兼容 LT 写法和十六进制入口；自动仅一跳，手动可传递；不存在的目标不会被替代为其他层。
- 非法或未知入口与另一个有效入口共存时，保留未知内容并允许有效路径。
- 真实协调器的 preview/prepare/export 均拒绝；已有目的文件逐字节保留、缺失目的文件不创建；加密记录重新打开后仍是原草稿、原文不变、无新增 artifact；同一协调器随后可完成合法导出。

## 官方运行交叉核验

实际运行官方 [vial-gui any_keycode.py](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/any_keycode.py)，先用 `recreate_keyboard_keycodes` 初始化 Vial 6、32 层合成键盘，再调用 `Keycode.deserialize(..., reraise=True)` 和 `serialize`：

- `MO/TG/DF/OSL/TT(1,2)` 官方均因多余参数抛出 `TypeError`。
- `LT(16,KC_A)` 官方得到 `0x4004` / `LT0(KC_A)`，并非层 16。KeyRecord 继续拒绝超范围表达式，不引入官方表达式求值器。
- `LT(1,USER00)` 和 `LT(1,MO(0))` 官方分别得到 `LT1(KC_NO)`、`LT1(KC_3)`。这两项是 KeyRecord 有意不支持的表达式，不能称为官方不支持；拒绝解析后同样不得授予访问。
- `MO(1)` 得到 `0x5221`；`LT(1,KC_A)` 与 `LT1(KC_A)` 均得到 `0x4104`，与合法控制组一致。

## 验证记录与边界

失败先行：4 个新增测试在旧代码上产生 38 个失败断言；其中后续合法导出遇到 `invalidState`，因为旧代码已错误推进状态。首次修复后测试发现哨兵文本不能通过固件文件解析器读取，测试改为直接读取目的文件字节，不改变产品行为或断言要求。相关回归日志最终单独串行执行，避免早期并行执行共用日志路径造成混杂。

可复现命令：`swift test --filter 'KeyRecordMappingsTests|KeyRecordDeviceReadTests|ProductBoundaryTests'`。离线证据位于 `/private/tmp/keyrecord-reachability-{discovery,red,public,official,tests-final,native,xcode}.log`，公开 API 驱动与官方核验脚本位于 `/private/tmp/keyrecord-to-public/Sources/ReachabilityDiscovery/main.swift` 和 `/private/tmp/keyrecord-reachability-official.py`。原生 App 沿用现有流程夹具，截图在 `/private/tmp/keyrecord-reachability-qa/`；它们是已有流程回归，不是本缺陷专属原生场景。PR 和 main CI 的最终结果以 GitHub 精确提交的运行记录为准。

生产支持目录仍为空，真实连接工厂默认 nil；本轮仅使用合成文件、模拟端点、内存密钥和临时加密存储。没有真实 HID、用户配置、Keychain、捕获、卸载或签名发布操作。G2/G3/G4 与完整 v1 资格仍未建立；同 UID 变化、非原子分块及无编号重复报告仍需后置真实验证。
