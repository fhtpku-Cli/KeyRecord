# Vial 编码器只读回与完整比较

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

状态日期：2026-10-14，Asia/Shanghai。起点为 [PR #32](https://github.com/fhtpku-Cli/KeyRecord/pull/32) 合并提交 `731d160c6f9c090508964c5b2e4f125dd1c1fc03`，其[主干 CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38457737893) 已成功。本批在任务独立工作树和 `codex/vial-encoder-read` 分支实施，主目录历史改动保持只读。

## 行为

此前设备定义解析会拒绝编码器，导出解析和完整比较只覆盖矩阵键。本批增加独立的 `FirmwareEncoderSlot`（层、索引、方向）和 `FirmwareEncoderDirection`，编码器不使用矩阵坐标，也不进入矩阵修改草稿。官方 `encoder_layout` 必须与矩阵层数一致、各层索引数量一致、每项恰好两个字符串或一对 `-1` 空洞；半空洞、错误类型及不完整方向拒绝。

独立设备定义保留可见编码器索引及方向。当前支持的 KLE `a=0/4` 中，raw label 9 映射到归一化 label 4 的 `e`；没有改变这个位置。索引允许 0…255、方向只允许 0/1。与官方读取行为相同：即使布局仅显示一个方向，仍读取该索引的顺／逆时针两个值。每层文件占用索引和完整方向必须匹配独立定义，文件中的空洞不会触发查询，缺少编码器或错位在矩阵键图查询前拒绝。

新请求仅为 `FE 03 layer index` 的 typed `GET_ENCODER`，没有 `SET_ENCODER` 或任意命令构造入口。回应前四字节分别是顺／逆时针大端 16 位值，无请求回显；每份报告继续经过取消、隐私授权及长度检查。最终身份和层数检查覆盖矩阵及编码器读取全过程。沿用无编号响应不能验证同 UID 动态变化或原子快照的限制。

观察值分开携带矩阵和编码器字典；既有加密事务要求两组槽位完整，键码别名归一化后两组均匹配才为 `verified`。矩阵匹配但编码器变化记为 `externallyChanged`；两组均等于原始副本则为 `failed`。缺失编码器观察不写验证证据。矩阵修补保持编码器、宏及未知字段原始字节。

没有新增 hash、冻结 contract、baseline 或工程门禁，保留原有隐私、支持目录、加密副本和事务措施。默认连接工厂仍 nil、生产支持目录仍为空。

## 实际验证

77 项不同的相关离线测试通过：18 项设备读取、17 项协议适配、19 项固件操作、4 项隐私、6 项模块边界，以及 13 项 App/原生测试。变体和重复执行不重复计数。未签名 arm64 App `build-for-testing` 成功。

| 场景 | 实际结果 | 产物 |
|---|---|---|
| 原生读回按钮 AXPress | 17 份模拟报告读取 XZ 定义、矩阵及编码器，实际模型进入 Verified；主会话已查看截图 | `/private/tmp/keyrecord-encoder-native.log`、`keyrecord-encoder-qa/vial-encoder-readback-en.png` |
| 编码器变化、矩阵正确 | App 和加密重开均为 externallyChanged | 同一 native 日志；`keyrecord-encoder-core.log` |
| 独立索引不一致或导出缺失编码器 | 查询键图前拒绝，连接关闭一次，未写验证时间 | 同一 native 日志、core 日志 |
| 编码器报告暂停后的任务取消或隐私清空 | 终止连接，无后续报告；迟到输入不能写证据 | 同一 native 日志 |
| 两层、稀疏索引、单个可见方向、大端响应 | 每层仅查询索引 2，读取两个方向；空洞、畸形层/方向、越界索引拒绝 | core 日志 |
| 官方源码方法往返与公开 API | 20 份模拟 HID 报告、196 字节 XZ、14 个矩阵及 4 个编码器槽，验证后加密重开一致 | `/private/tmp/keyrecord-encoder-roundtrip.log`、`keyrecord-encoder-official.log` |
| 构建、原生回归 | unsigned arm64 build-for-testing 与旧 nil 工厂、取消、重试、文件场景通过 | `/private/tmp/keyrecord-encoder-build.log`、native 日志 |

使用官方 vial-gui 源码提交 [`aef8222a2d0429a183b2ed692d5f9efcfd383f08`](https://github.com/vial-kb/vial-gui/tree/aef8222a2d0429a183b2ed692d5f9efcfd383f08)。`Scripts/vial-official-roundtrip.py --encoders --definition ...` 执行未改写的 `save_layout`、`restore_layout`、`reload_keymap` 方法和实际 KLE 反序列化，核对保存空洞、标签映射、每层查询顺序及方向端序。GUI、设备写入、宏编辑和实际 `set_encoder` 为记录端口，不代表官方 GUI 对稀疏布局的设备恢复兼容性；脚本没有调用实际 HID。

往返初次夹具使用官方序列化的 `RSFT(KC_QUOTE)`，实际驱动按既有限键码方言拒绝为 `unsupportedOutput`。换为已支持的 `RCTL(KC_C)` 后同一路径通过；未扩展或绕过未知键码拒绝。普通编码器协议测试仍使用不同高低字节的 raw hex 值验证端序。

一次“暂时移除编码器比较以证明回归会失败”的实验补丁被自动审批拒绝，理由是会削弱完整性校验；补丁未执行，也没有以其他方式执行。没有修复前红测试证据，不能把该实验记为通过。最终回归直接执行完整实现的成功与拒绝场景。

源码自审与运行审计按 review-work/debugging 方法在主会话完成，记录在 `/private/tmp/keyrecord-encoder-review.md`，按最终提交 SHA 绑定；GitHub PR/主干 CI 状态以实际检查为准。

## 证据边界

没有真实 HID open/send/枚举、捕获、真实配置/Keychain 修改、卸载、签名公证或发布。编码器只读离线增量不取得生产设备支持、后台效果、G2/G3/G4 或 v1 资格。原生 IOHID 时序/权限、完整复杂 KLE、宏及动态子协议、VIA 设备、官方 GUI 恢复和真实静止配置验证继续后置。所有文件、密钥与端口均为合成夹具或专用临时存储。
