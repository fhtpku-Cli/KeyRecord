# Vial 6 协议与官方格式离线集成

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

状态日期：2026-10-13，Asia/Shanghai。本批从已核对的主干 `877900c755d2240f056503ecad24dcfc8f6856fb` 开始，[合并后 CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38418731109) 已成功。实施在本任务隔离工作树和 `codex/backend-offline-integration` 分支，主目录只读。

## 缺口与实现

此前正式模块只有注入好的键位快照，没有把协议响应转换成观察值的适配器。官方 Vial 保存函数在未使用的矩阵位置写入数字 `-1`，此前正式解析器只接受字符串，会拒绝正常文件。本批选择 Vial 6 / VIA 9 的键图读回为最小完整增量；没有重复 Karabiner 版本读取或扩入完整密码备份。

- `FirmwareDocument` 保留 `-1` 的字节和完整矩阵尺寸，空位不进入可编辑/比对槽位；其他非字符串值仍拒绝。修补只替换选中字符串，宏、动态内容、未知字段及空白原样保留。
- `FirmwareVersionProvider` 从 Vial 文件读取格式、VIA/Vial 协议和已实现的 Vial 6 方言；VIA 文件只能确认布局 JSON 格式。定义版本、导入器构建和 VIA 设备协议/键码版本需独立输入。App 默认保留这些部分事实，缺少轴仍不合格。
- `VialReadbackAdapter` 接受独立定义的矩阵行列数及 `VialReadTransport`，实际查询 VIA 协议、Vial 身份、层数、完整键图及最后身份/层数。32 字节报告，每块键图最多 28 字节；UID/协议小端，偏移/键码大端。矩阵/文件版本不符、未知协议、错 UID、短/长包、错回显头、重绑定、传输错误、并发和取消均不产生观察值。
- 请求类型只提供协议、身份、层数及键图读取，没有任意字节构造器或写入/解锁/捕获命令。每次交换前后沿用现有隐私授权，取消检查覆盖查询及发布。未来传输端负责超时、HID report-ID 包装、响应关联和设备绑定；本批没有实现或启用 HID 端口。
- Vial 6 比对按 16 位键码规范化标准键、别名、有限修饰组合、层入口和十六进制字符串，避免 `KC_ENT` / `KC_ENTER` 等拼写造成误判。未实现命名/自定义动作拒绝比对；十六进制层入口和重启/清空键继续受保护。空键和可达层沿用原有规则。
- App 可注入协议适配器，既有读回按钮从加密原始副本取得矩阵/槽位，再执行查询、隐私检查和现有完整键图比对/证据恢复。旧快照接口保留，正式组成仍使用空支持目录和 nil 设备端口。

没有新增 hash、冻结 contract、baseline 或工程 gate，也没有削弱既有措施。模块图测试只更新测试工具位置；工具不发布为产品，也不能成为产品模块依赖。

## 一手来源及执行范围

读取了[官方 Vial 保存/恢复/协议代码](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/protocol/keyboard_comm.py)、[Vial 6 键码表](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/keycodes/keycodes_v6.py)和[表达式解析](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/any_keycode.py)，并对照[Vial-QMK VIA 处理](https://github.com/vial-kb/vial-qmk/blob/vial/quantum/via.c)和[身份响应](https://github.com/vial-kb/vial-qmk/blob/vial/quantum/vial.c)。[VIA 官方保存/载入](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/components/panes/configure-panes/save-load.tsx)确认文件没有设备协议或导入器构建；本次没有执行 VIA GUI 往返。

`Scripts/vial-official-roundtrip.py` 从本地官方 checkout 提取并原样执行 `save_layout` / `restore_layout` 的 AST，同时导入官方 Keycode/AnyKeycode 和官方固定提交的 simpleeval。GUI、HID 和功能编辑器未导入；宏/动态特性端口使用记录器保留非空合成内容，不证明这些设备子协议。旧 simpleeval 打包脚本与 Python 3.13 不兼容，改为直接加载[官方固定提交的纯 Python 源码](https://github.com/danthedeckie/simpleeval/blob/41c99b8e224a7a0ae0ac59c773598fe79a4470db/simpleeval.py)，没有改用户 Python 环境或项目依赖。

实际闭环：官方保存生成含 UInt64 最大值 UID、别名、Vial 6 元数据和空位的合成文件 → 公开 API 保留/预览/导出/声明 → 模拟报告读回/比对 → 加密状态重开 → 官方恢复接受修改 → 官方重导出并逐槽按官方键码比较，检查 UID、空位、宏和动态夹具字段。

## 实际验证与自审

47 项不同的相关离线测试通过，重复执行不重复计数。

| 验证 | 结果 | 产物 |
|---|---|---|
| 适配器/格式/版本/拒绝/隐私/并发/取消/端序 | 13 例通过；320 字节图分 12 块，跨高位偏移，最后 12 字节块；14 槽场景忽略两空位 | `/private/tmp/keyrecord-backend-integration-core.log` |
| 既有固件操作 | 19 例通过 | 同上 |
| 隐私及模块边界 | 4 + 6 例通过 | 同上 |
| 合成产品部分轴/默认只读、新适配器原生按钮、晚回包隐私及既有保留/按钮 | 5 例通过，无跳过 | `/private/tmp/keyrecord-backend-integration-native.log` |
| 未签名 arm64 App build-for-testing | 成功 | `/private/tmp/keyrecord-backend-integration-build.log` |
| 公开 API 驱动 | 成功，14 槽比对、加密重开、原始字节保留 | `/private/tmp/keyrecord-backend-integration-probe.log` |
| 官方生成、恢复和重导出 | 成功 | `/private/tmp/keyrecord-backend-integration-official-generate.log`、`/private/tmp/keyrecord-backend-integration-official.log` |
| 原生截图 | 主会话已查看，显示 Verified、读回按钮及原有导入不等于部署说明 | `/private/tmp/keyrecord-backend-integration-qa/vial-protocol-readback-en.png` |

包测试命令为 `swift test --scratch-path /private/tmp/keyrecord-backend-integration-swift --filter 'VialReadbackAdapterTests|FirmwareOperationTests|ProductBoundaryTests|PrivacyBoundaryTests'`。另临时恢复本任务自己的旧空位解析逻辑，同一空位用例因数字无法解码为字符串失败（`/private/tmp/keyrecord-backend-integration-red.log`）；恢复修复后通过（`/private/tmp/keyrecord-backend-integration-green.log`）。

测试专用 `KeyRecordFirmwareIntegrationProbe <synthetic-original.vil> <patched-output.vil>` 使用公开 API、内存密钥、专用临时对象存储和模拟传输。`--help` 正常，无参数退出 2 并报告 `invalidDocument`。临时根目录由存储模块自行创建，先 bootstrap 后 seed，沿用权限/旧数据保护。导出需要系统书签支持，沙箱书签拒绝通过已授权测试权限解决。

原生场景执行 AXPress 并检查六条协议请求、状态及导出字节。新增 UI 用例初次在异步主执行器调用同步渲染等待出现四次超时；改用仓库既有同步原生测试模式后五例通过，没有放宽断言或超时。构建保留已有 ProductComposition/FlowTestComposition/Phase1FlowHostlessTests 及旧捕获相关警告。LSP daemon 不可达，未声称 LSP 通过；Swift/Xcode 实际编译无错误。

主会话按 review-work/debugging 方法自审矩阵、UID/端序、版本事实、所有槽位及别名、逐包隐私、取消/并发恢复、保护入口、结果事务和官方方法闭环。自审发现并补上独立行列尺寸校验，拒绝总字节数相同但行列不同的文件；对应拒绝用例通过。当前没有未解决的可行动问题。最终提交的主会话 review/运行验证记录为 `/private/tmp/keyrecord-backend-integration-review.md`，不增加产品门禁。

## 真实证据边界

正式支持目录仍为空。文件事实、官方源码方法往返、模拟报告和 CI 均不建立真实设备资格。实际 HID 端口还需独立定义读取/匹配、设备绑定、report-ID/超时/响应关联；Vial 0–5、未实现命名/自定义键码、完整编码器/宏/动态读回、VIA GUI/设备往返均未覆盖。分块读图不是设备原子快照，同 UID/层数的并行配置编辑不能靠身份检查排除，真实验证需在静止配置条件下观察。

没有真实卸载、用户数据或 Keychain 删除、日常配置修改、捕获、HID/设备读写或正式签名发布。完整 G2/G3/G4 和 v1 仍未合格。当前提交 PR/push CI 以本批 PR 为准；CI 运行包测试及 App 构建，不运行本地原生窗口用例。
