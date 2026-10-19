# Vial 既有入口前导空白保护（2026-10-15）

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

## 修复范围

`FirmwareDocument.patch(automatic: false)` 曾允许把带前导空格、Tab 或换行的 `MO(1)`、`LT1(KC_C)`、`TG(1)`、`TO(1)`、`TT(1)`、`DF(1)`、`OSL(1)` 覆盖为 `KC_C`。JSON 字符串解码保留空白，而既有名称保护直接匹配原始前缀，导致漏判。

现仅在 Vial 6 既有入口保护分类时去除首尾空白，并为 LT 名族使用同样的保护判断。普通解析、层可达性、输出许可仍使用原始输入；没有开放表达式、扩大设备权限、改变 VIA 或其他方言。保留 OSM 对未获支持拼写的既有保护，不把归一化后的 OSM 当成合法动作。没有新增 hash、contract、baseline 或 gate。

## 实际执行证据

- 新增公共 patch 回归：22 个名称 × 空格、Tab、换行；验证解码保留原文、解析仍拒绝、自动及手动覆盖均为 `protectedEntry`、新输出被拒绝、目标层仍不可达。修复前实际出现 96 个失败断言，包含手动覆盖未抛错及自动路径错误类别；修复后通过。
- 81 项映射测试、18 项模拟设备读取测试、6 项产品边界测试通过，覆盖原有 LM、PDF、static、boot、LT、普通 raw 和手动替换行为。
- 独立 Swift 公共 API 驱动：七种无空白名称及 21 种前导空白形式均拒绝；`KC_A`、`0x0004`、合法 `OSM(MOD_LCTL)` 仍能手动替换；非法槽位拒绝。实际编译与执行退出 0。
- 未签名 arm64 `build-for-testing` 成功；本机 `KarabinerMappingFlowTests` 65 项通过，包含 AXPress、完整矩阵/编码器模拟回读、加密记录重开、取消与隐私迟到响应。这些原生场景使用原有合成夹具；本次空白漏洞由新增公共接口回归和独立驱动直接验证。
- 三个触及工程 Swift 文件 LSP 无错误，`git diff --check` 通过。临时独立 Swift 包实际编译成功，但 SourceKit 仍报告无法索引本地依赖，不能计为该临时包的 LSP 通过。Python LSP 沿用此前不安装的决定，以实际执行验证。

官方源码 `vial-gui` 提交 `aef8222a2d0429a183b2ed692d5f9efcfd383f08`：初始化两层键盘后，实际调用 `Keycode.deserialize(..., reraise=True)` 和 `serialize`。上述七类 28 个输入全部接受；其中 `TO(1)` 的精确名称返回 `0x5201`，三种前导空白形式经表达式路径返回 `0x5211`。其余六类的空白输入与原名称编码一致。这是官方名称表与表达式的差异，本轮只保护这些入口，不据此放宽解析或调整编码。初次探针假设二者一致，断言在 TO 处失败；修正探针为分别记录两条路径后完整执行成功。

本地证据：`/private/tmp/keyrecord-ws-{red,tests,public,official,xcode,native}.log`；驱动 `/private/tmp/keyrecord-ws-public/`；截图 `/private/tmp/keyrecord-ws-qa/`。最终主会话自审、精确源提交和 CI 记录另存 `/private/tmp/keyrecord-ws-review.md`。

## 资格边界

本轮仅离线安全工程。生产支持目录仍为空，默认连接 factory 为 nil；未执行真实 HID open/send/枚举/捕获，未访问真实配置或 Keychain，未签名、公证或发布。G2/G3/G4 与 v1 仍未合格。真实设备、同 UID 动态变化、非原子分块快照和无编号重复报告仍需静止配置条件下的真实验证。CI 不运行 App XCTest，本机原生证据单独记录。
