# Vial 持久默认层名称离线兼容 — 2026-10-14

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

基于 PR #38 合并提交 `33dd72f8f58a05f3b81c53c76a3f0415f0bd5afa`。该提交合并后的 main CI 38566135064 已 completed/success，本轮 fetch 核对一致。

## 问题与修复

官方 Vial 6 按设备初始化后，PDF(0)…PDF(31) 是持久默认层 canonical 名称，raw 范围为 0x52e0…0x52ff。官方 `KEYCODES_LAYERS` 将它们标为 requires_feature=persistent_default_layer。本轮以合成 32 层键盘声明该 feature，逐个 serialize/deserialize(reraise=True) 往返成功；这不是实际设备 feature 或生产支持证明。

官方 any_keycode.functions 实际未注册 PDF，PDF(0x1)、PDF (1)、前导空格和未知参数均抛 FunctionNotDefined，PDF(01) 抛 SyntaxError。Swift 因而只匹配 32 个精确 canonical 名称，没有数值表达式、参数别名或泛化层协议。原 layerEntry 和修补输出限制保留，PDF 不授予自动或手动进入另一层的权限。

修复前新回归实际执行 3 项，产生 92 个失败断言，其中 32 个是 canonical 解析异常；其余是入口保护错误或实际手动覆盖成功。合法 PDF(0/1/31)、非法 PDF(32/01/0x1/未知/嵌套)、空格及 Tab/换行形式都能因解析失败绕过既有手动保护。有效 JSON 由 JSONEncoder 生成，未以格式拒绝替代行为证据。旧公开探针实际 exit 2 / unsupportedOutput。

生产源码仅增加两行：精确 canonical 解析，以及在解析前保护 PDF 名称族（识别前导空白）。原 raw 范围、OSM/LT 保护、方向/深度/基础子键限制未削弱；没有新增 hash、冻结 contract、baseline 或 gate。

## 实际验证

| 场景 | 结果 | 本机证据 |
| --- | --- | --- |
| 官方契约和修复前复现 | 32 名称实际往返；PDF 表达式未注册；旧公开探针 unsupportedOutput；新回归 92 失败断言 | `/private/tmp/keyrecord-persistent-layer-official-parameters.log`、`keyrecord-persistent-layer-red.log`、`keyrecord-persistent-layer-probe-red.log` |
| 包测试 | 12 键码、27 适配、19 固件、18 设备、4 隐私、6 产品边界，共 86 项零失败；最终官方夹具驱动的 12 键码复核零失败 | `/private/tmp/keyrecord-persistent-layer-core.log`、`keyrecord-persistent-layer-keycode-final.log` |
| 原生 App | 27 项零失败，实际 AXPress 后 Verified/日期；17 模拟报告、close once | `/private/tmp/keyrecord-persistent-layer-native.log`、`keyrecord-persistent-layer-qa/vial-persistent-layer-readback-en.png` |
| 独立官方字节 | 640 big-endian 字节、67 模拟报告、196 字节 XZ；224 矩阵与 64 编码器方向槽完整比较、加密重开 | `/private/tmp/keyrecord-persistent-layer-generation.log`、`keyrecord-persistent-layer-probe.log` |
| 全名称公开 API | 32 名称逐个用官方独立 raw 字节闭环和加密重开；10 非法动作拒绝；帮助 exit 0、缺参 exit 2 | `/private/tmp/keyrecord-persistent-layer-public-qa.log` |
| 官方方法与既有夹具 | 官方 save/restore/reload 通过；基础、普通修饰、modifier-tap、OSM 夹具与仓库文件逐字一致 | `/private/tmp/keyrecord-persistent-layer-restore.log`、`keyrecord-persistent-layer-legacy.log` |
| 构建/诊断 | 未签名 arm64 build-for-testing 成功；4 触及 Swift 文件 LSP 无错误 | `/private/tmp/keyrecord-persistent-layer-build.log`、主会话工具记录 |

共 113 项不同包/App 场景通过，不重复加总中间复核。矩阵与编码器的 expected、原始未应用、matrix external、encoder-only external 完整比较及加密重开均通过。原生场景验证 PDF(USER00) 不产生 verifiedAt、取消/隐私后的迟到响应不写证据、连接关闭一次。非法数值、别名、非基础/嵌套/方向/深度和既有 OSM 数字保护回归保留。官方脚本帮助通过，generate/check 同时输入实际 exit 2。

最初 sandbox 内 Swift 因默认 ModuleCache 写权限失败，公开探针因合成文件书签权限失败；随后通过正常 require_escalated 运行。环境错误不是红绿证明，以上失败断言和 unsupportedOutput 来自实际执行的业务场景。

## 范围与限制

官方源码 SHA `aef8222a2d0429a183b2ed692d5f9efcfd383f08`。脚本新增 --persistent-layer-keycodes 和 --persistent-layer-fixture，只是离线工具。官方 save_layout、restore_layout、reload_keymap 原方法未改写；宏/编码器设置仍由 fixture port 承接，KleSerial 实际执行，不证明真实 GUI 恢复或设备写入。

生产支持目录为空、连接工厂 nil；没有真实 HID 打开/发送/枚举/捕获、用户配置/Keychain/卸载、签名公证或发布。G2/G3/G4 与 v1 继续未合格。非原子分块快照、无编号重复报告、同 UID 动态变化仍需要静止配置下的真实验证。

既有 Keychain 弃用、Sendable、FlowTestComposition、BackendAnalysisView、ProductPersistence、observed 捕获及 AppIntents 警告保留，未抑制或跳过测试。Python/JSON LSP 用户此前拒装，本轮未安装；脚本实际执行及夹具比较通过。
