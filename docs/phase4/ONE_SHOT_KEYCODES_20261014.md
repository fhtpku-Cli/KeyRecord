# Vial 一次性修饰键名称离线兼容 — 2026-10-14

基于 PR #37 合并提交 `0745093c755c981c8c92c18af1724cd47b18c32a`；源提交 `cc4113f45c1fb74ebbfe7b62fc7a61cac9e12904` 的 push/PR CI 均成功，721 项包测试零失败。合并后主干 CI 38535796294 已 completed/success。

## 问题与修复

官方 Vial 6 按设备初始化后，将 30 个一次性修饰键保存为 OSM(MOD_LCTL)、OSM(MOD_HYPR) 或 OSM(MOD_RCTL|MOD_RSFT) 等名称。官方 serialize/deserialize(reraise=True) 逐个实际往返成功，而修复前公开离线探针逐个返回 unsupportedOutput。新增键码回归修复前有 30 个失败断言。

Swift 只识别官方实际保存的 30 个 canonical 名称，覆盖左/右各 15 种非空组合，复用既有 raw hex 归一化和完整矩阵/编码器比较。不引入通用表达式求值，也不扩充可修补的自动或手动输出集合。旧 OSM(MOD_MEH) 拒绝预期更新为官方兼容证明，未知 OSM(USER00)、数字、算术、嵌套及方向混用仍拒绝。同方向重排、空格和 MEH/HYPR 展开虽可由官方规范化，亦未扩大到本轮 canonical 名称范围。

官方参数实验揭示两个边界：左右混用 OSM(MOD_LCTL|MOD_RCTL) 会保存为 OSM(MOD_RCTL)；OSM(0x40)、OSM(64) 和 OSM (0x40) 实际都保存为 PDF(0)，raw 值 0x52e0。前导空格、Tab、换行形式也有相同结果，不能将数字 OSM 当作普通一次性修饰键。

自审实际复现：解析失败会让这些 PDF 别名绕过原有手动入口保护。修复前 3 个普通形式有 6 个失败断言；补充正确转义的 JSON 夹具后，3 个前导空白形式同样有 6 个失败断言。现有 protectedEntry 对 OSM 名称族先识别前导空白；未在 canonical 集合内的形式保留入口保护，不能因解析失败获得覆盖权限。30 个合法名称仍可正常参与读回，不能授予另一层可达性。没有新增 hash、冻结 contract、baseline 或 gate。

## 实际验证

| 场景 | 结果 | 本机证据 |
| --- | --- | --- |
| 官方名称和修复前复现 | 30 名称实际往返；旧公开探针 exit 2；新键码回归 30 失败断言 | `/private/tmp/keyrecord-one-shot-discovery.log`、`keyrecord-one-shot-red.log`、`keyrecord-one-shot-probe-red.log` |
| 安全入口复现 | 普通数字形式 6 失败断言；有效 JSON 的前导空白形式 6 失败断言；修复后通过 | `/private/tmp/keyrecord-one-shot-protection-red.log`、`keyrecord-one-shot-whitespace-valid-red.log`、`keyrecord-one-shot-final-core.log` |
| 包测试 | 10 键码、25 适配、19 固件事务、18 设备、4 隐私、6 产品边界，共 82 项零失败 | `/private/tmp/keyrecord-one-shot-final-core.log` |
| 原生 App | 24 项零失败；实际 AXPress 后 Verified/日期，17 模拟报告、close once | `/private/tmp/keyrecord-one-shot-final-native.log`、`keyrecord-one-shot-final-qa/vial-one-shot-readback-en.png` |
| 独立官方字节 | 40 big-endian 字节、20 模拟报告、196 字节 XZ；14 矩阵与 4 编码器方向槽完整比较、加密重开 | `/private/tmp/keyrecord-one-shot-generation.log`、`keyrecord-one-shot-probe.log` |
| 全名称公开 API | 30 名称逐个使用官方独立 raw 字节走完整闭环；8 个危险/未知动作拒绝；帮助 exit 0、缺参 exit 2 | `/private/tmp/keyrecord-one-shot-final-public-qa.log` |
| 官方方法与既有夹具 | 官方 save/restore/reload 实际通过；基础、普通修饰及 modifier-tap 夹具与仓库文件逐字一致 | `/private/tmp/keyrecord-one-shot-restore.log`、`keyrecord-one-shot-legacy.log` |
| CLI 边界 | 官方脚本帮助成功、generate/check 互斥输入 exit 2 | `/private/tmp/keyrecord-one-shot-help.log`、`keyrecord-one-shot-invalid.log` |
| 构建/诊断 | 未签名 arm64 build-for-testing 成功；4 触及 Swift 文件 LSP 无错误，安全保护 delta 再核对 2 文件无错误 | `/private/tmp/keyrecord-one-shot-final-build.log`、主会话工具记录 |

共 106 项不同相关包/App 场景通过，未重复加总中间修复轮次。完整比较覆盖 expected、原始未应用、矩阵外部变化及编码器单独外部变化，加密重开保持结果。原生场景另外验证未知 OSM(USER00) 不产生 verifiedAt、隐私/取消后的迟到响应不写证据，连接关闭一次。合法 OSM、非法 OSM、既有 MO/LT/启动/清除及 raw PDF 入口的自动和手动输出/保护/可达性边界均有实际回归。

## 范围与限制

官方源码 SHA `aef8222a2d0429a183b2ed692d5f9efcfd383f08`。Scripts/vial-official-roundtrip.py 增加 --one-shot-keycodes 和 --one-shot-fixture，仅是离线开发工具；官方 save_layout、restore_layout、reload_keymap 方法未改写，宏及编码器设置仍为夹具端口。真实 GUI 恢复、设备效果和后台行为未验证。

生产支持目录为空、连接工厂 nil 的默认组成保留；没有真实 HID 打开/发送/枚举/捕获、用户配置/Keychain/卸载、签名公证或发布。G2/G3/G4 与 v1 继续未合格。非原子分块快照、无编号重复报告与同 UID 动态变化的真实验证限制保留。

构建保留既有 Keychain 弃用、Sendable、BackendAnalysisView、ProductPersistence、observed 捕获及 AppIntents 警告；没有删除/跳过测试或抑制诊断。Python/JSON LSP 用户此前拒装，本轮未安装，脚本实际执行、夹具比较通过。增加 Tab/换行夹具时曾遗漏 JSON 转义，实际遇到 malformed 后修正为 JSONEncoder 编码；有效 JSON 中的安全绕过已单独复现，不以格式拒绝代替行为证明。
