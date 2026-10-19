# Vial 静态层动作离线兼容

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

基于 main `1cb33c687ed0f8fdd18b0cce0c4ba22afdf6584f`，本轮在独立工作树执行，主目录未修改。

## 问题与修复

官方 vial-gui `aef8222a2d0429a183b2ed692d5f9efcfd383f08` 按四层合成键盘初始化后，FN_MO13、FN_MO23、QK_LAYER_LOCK 分别往返为 0x7c77、0x7c78、0x7c7b。FN 两项在官方层数至少为四时注册；层锁声明 requires_feature=layer_lock。合成 feature 不代表真实设备支持。

官方条目虽声明 QK_LLCK 别名，实际 deserialize(reraise=True) 抛 NameNotDefined，默认模式返回 0。因此本轮只接受三个精确 canonical 名称，不接受该别名、参数、空白变体或嵌套动作。

修复前实际执行三项新回归，产生 43 个失败断言：三个名称解析失败，名称及 raw 保护缺失，17 种合法或未支持入口均可手动覆盖。同一公开探针返回 exit 2 / unsupportedOutput。JSONEncoder 生成有效 JSON，未以格式失败替代入口行为证据。

生产改动仅限 VialKeycodeDialect：新增三个名称的静态映射，解析前保护 FN_MO、QK_LAYER_LOCK、QK_LLCK 名称族，并保护三个 raw 值。沿用 FirmwareDocument.patch 的既有保护位置；不增加 hash、冻结 contract、baseline 或通用 gate，不扩大输出白名单或层可达性，不弱化已有安全措施。

## 已执行验证

| 场景 | 结果 | 本机证据 |
| --- | --- | --- |
| 修复前复现 | 三项回归、43 失败断言；公开探针 unsupportedOutput | /private/tmp/keyrecord-static-layer-red.log；keyrecord-static-layer-probe-red.log |
| 相关包回归 | 14 键码、29 适配器、19 固件事务、18 设备、4 隐私、6 产品边界，共 90 项通过 | /private/tmp/keyrecord-static-layer-core.log；keyrecord-static-layer-boundaries.log |
| 原生 App | 31 项通过；实际 AXPress 后 Verified/日期，17 个模拟报告、连接关闭一次 | /private/tmp/keyrecord-static-layer-native.log；keyrecord-static-layer-qa/vial-static-layer-readback-en.png |
| 四层独立官方字节 | 80 big-endian 字节、196 字节 XZ、23 模拟报告；28 矩阵及 8 编码器方向槽完整比较并加密重开 | /private/tmp/keyrecord-static-layer-probe.log |
| 单名称公开闭环 | 三个名称逐个以官方 raw 驱动公开 API、加密重开及官方 restore/save/reload；12 种非法编码器名称拒绝；帮助/缺参通过 | /private/tmp/keyrecord-static-layer-public-qa.log |
| 既有夹具 | basic、modifier、modifier-tap、OSM、PDF 和新静态层夹具重新生成后逐字一致 | /private/tmp/keyrecord-static-layer-legacy.log |
| 构建与诊断 | 未签名 arm64 build-for-testing 成功；四个触及 Swift 文件 LSP 无错误；diff --check 通过 | /private/tmp/keyrecord-static-layer-build.log；主会话工具记录 |

共 121 项不同包/App 场景通过。适配器覆盖 expected、未应用原配置、矩阵外部变化、仅编码器外部变化及加密重开，缺少编码器观察仍被拒绝。原生场景覆盖 QK_LLCK 不产生 verifiedAt、取消及隐私后的迟到响应不写证据。

原生夹具沿用单层传输形状，用来验证名称比较及事务边界；独立官方夹具为四层。单层模拟不证明 FN 动作的真实层效果或设备可用性。

公开负例的首次临时驱动让模拟端自行解析非法编码器名称，得到 invalidReport；最终驱动改为提供独立的合法 raw 报告，实际由产品文档比较路径返回 unsupportedOutput。没有更改产品代码或放宽预期来掩盖此区别。

## 范围

官方 save_layout、restore_layout、reload_keymap 方法未改写；宏/编码器设置由离线 port 承接，KleSerial 实际执行。证据只覆盖离线兼容，不证明真实 GUI 恢复或设备写入。

生产支持目录仍为空、连接工厂默认 nil。未打开、发送或枚举真实 HID，未触及真实配置、Keychain、卸载或签名发布。G2/G3/G4 与 v1 继续未合格；真实 FN/层锁行为、无编号重复报告、同 UID 动态变化、非原子分块快照仍待静止配置下的真实验证。

既有构建警告保留，未抑制或跳过测试。Python/JSON LSP 此前被用户拒装，未安装；Python 脚本以实际执行和生成物比较验证。PR/push CI 与合并后 main CI 将分别核对，不能以本机结果代替。
