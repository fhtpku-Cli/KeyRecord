# HID 传输端与独立设备定义读取

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

状态日期：2026-10-14，Asia/Shanghai。

[PR #30](https://github.com/fhtpku-Cli/KeyRecord/pull/30) 已按用户确认合并为 `3415d393ab3b2424b78f66ef61a75b6b58ddab16`，[合并后主干 CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38429930883) 成功。本批复用当前窗口及干净受管工作树，从实际主干新建 `codex/hid-definition-offline`；上下文和端口连续，无需新开窗口。主目录保持原 HEAD 和 215 项历史改动，只读。

## 源码增量

新增独立 `KeyRecordDeviceRead` 模块，IOKit 依赖没有加入分析、存储或映射模块。App 正式组成仍不打开设备；新库可通过已有读回注入接口供后续组成使用。

- `IOKitVialHIDEndpoint.open` 只针对调用方明确选择的 registry entry，核对 VID/PID、Raw HID usage page `0xFF60` / usage `0x61` 及 32 字节报告尺寸；没有 manager 枚举或键盘事件监听。原生源码调用异步 `IOHIDDeviceSetReportWithCallback`，Report ID 单独传 0，报告是 32 字节，不复制 hidapi 的额外 ID 前缀。发送报告本身是系统 I/O 写入，命令内容只包含已声明的非修改查询，不宣称字面意义的“没有 I/O 写入”。
- 原生输入、移除、发送完成和取消回调在独立串行队列处理；输入和输出缓冲保持固定地址，取消处理器等事件排空后才释放 callback 所有权及缓冲。立即失败的发送按 Apple 源码的“不再回调”分支清理。timeout 使用 SDK 声明的毫秒，并拒绝超过底层 UInt32 范围的值。
- `VialHIDTransport` 复用 `VialReadTransport`，一次只允许一个交换；发送完成和 32 字节输入均成功后才返回，支持两种回调顺序。错误报告 ID/长度、重复/无待处理输入、断开、发送错误、超时和取消关闭连接。Vial 的定义/身份响应没有请求编号；连接出错后拒绝复用，迟到包不能满足下一次查询。没有重试、重新打开或自动重新选择设备。
- `VialReadRequest` 新增 `FE/01` 定义长度和 `FE/02` 定义页，页编号小端、每页 32 字节；仍没有任意请求构造或固件修改命令。
- `VialDefinitionReader` 从设备报告独立读取 VIA 9 / Vial 6 身份、压缩定义长度和全部页，再次检查身份。最多 128 KiB 压缩输入。`KeyRecordLimitedXZ` 调用 macOS SDK 自带 `liblzma.5` 的公开解码 ABI，限制 1 MiB 输出及 64 MiB 解码内存，并拒绝损坏、截断、额外尾部/拼接流；没有 Homebrew 或下载库的运行时依赖。
- 定义解析沿用有界 JSON 和重复字段保护，读取 VID/PID、矩阵及真实 KLE 位置。空 KLE 属性及 false decal 可读取；需要猜测标签位置的对齐、true decal、编码器标签、越界和无效结构拒绝。`vial-embedded-json` 是本地解析格式标识，原始定义没有因此得到虚构的官方版本号。
- `VialDeviceReadSession` 串行执行定义读取和键图读取；核对独立 VID/PID、行列及每一层的占用坐标，不能只凭相同字节数认定矩阵相同。随后进入已有协议适配器和完整键图比对/加密结果事务。使用者通过 `authorize` 传入现有隐私代次检查；定义查询前后和解压后的结果发布均检查。原始定义只在内存中，不新增持久化字段。

没有新增 hash、冻结 contract、baseline 或工程 gate，没有删除/削弱原有校验。请求的类型、串行交换、终止连接及资源上限针对实际 I/O/内存边界；不是用前置检查替代查询或解压执行。现有模块图测试只更新新库/C 桥和测试工具的依赖关系。

## 官方一手来源

- [Vial 官方报告包装和接口识别](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/util.py)，及[定义长度/分页/XZ 解压](https://github.com/vial-kb/vial-gui/blob/aef8222a2d0429a183b2ed692d5f9efcfd383f08/src/main/python/protocol/keyboard_comm.py)。
- 当前 Xcode SDK `IOKit.framework/Headers/hid/IOHIDDevice.h` 的 report ID、异步发送、毫秒参数、dispatch 激活/取消及 cancel handler 生命周期说明。
- [Apple IOHIDDevice 源码](https://github.com/apple-oss-distributions/IOKitUser/blob/323ead896d04424f87184d8f6ff0cce811aab106/hid.subproj/IOHIDDevice.c)，确认立即失败清理、固定回调 device、异步报告注册和取消行为；[Apple HID 插件实现](https://github.com/apple-oss-distributions/IOHIDFamily/blob/777ccd9698845aadf711e32d843c8c9b777431d9/IOHIDLib/IOHIDDeviceClass.m)将 UInt32 timeout 传入系统请求。
- [liblzma 公开单次解码 API](https://tukaani.org/xz/liblzma-api/container_8h.html)，及实际 SDK `usr/lib/liblzma.5.tbd` 的导出符号。SDK 不附 liblzma 头文件，因此仅在小 C 桥声明该公开 ABI；实际系统库已执行过解码和资源限制测试。

## 实际离线验证及自审

56 项不同的相关包测试通过，重复执行不重复计数：新设备读取 14 项、既有协议适配 13 项、固件操作 19 项、隐私 4 项、模块边界 6 项。命令：

```sh
swift test --scratch-path /private/tmp/keyrecord-hid-definition-swift --filter 'VialDeviceReadTests|VialReadbackAdapterTests|FirmwareOperationTests|ProductBoundaryTests|PrivacyBoundaryTests'
```

| 场景 | 实际结果 | 证据 |
|---|---|---|
| 发送/输入两种顺序；并发、取消、断开、发送错误；ID、长度、超时与迟到回调 | 交换只完成一次，故障连接关闭，后续查询零发送 | `/private/tmp/keyrecord-hid-tests.log` |
| 分页定义、大小/页边界、UID、VID/PID 和每层占用位置 | 176 字节 XZ 定义实际分六页；相同键数但空位不同的文件拒绝，错误 VID/PID 不读键图 | 同上 |
| 真实系统 XZ 解码 | 正常解码成功；压缩损坏/截断/尾部、1,048,577 字节展开产物及超过预算的字典拒绝 | 同上 |
| 定义解析 | 合法空属性和 false decal 成功，未知对齐/true decal/越界拒绝 | 同上 |
| 公开 API 完整驱动 | 官方合成原始文件 → 预览/导出/声明 → 模拟 HID 17 次报告交换 → 读取并解码 192 字节独立定义 → 14 槽比对 → 加密结果重开 | `/private/tmp/keyrecord-hid-probe.log` |
| 官方源码方法往返 | 官方 Vial 恢复接受产物，重导出后逐槽等价，宏/动态夹具由记录器保留 | `/private/tmp/keyrecord-hid-official-roundtrip.log` |
| 帮助/坏参数 | `--help` 退出 0，无参数退出 2 | `/private/tmp/keyrecord-hid-help.log`、`/private/tmp/keyrecord-hid-invalid.log` |
| 未签名 arm64 App build-for-testing | 成功，保持既有警告 | `/private/tmp/keyrecord-hid-app-build.log` |
| LSP | 新模块三份 Swift 文件，错误诊断 0 | 本轮工具结果；实际 Swift 编译同样通过 |

公开驱动沿用 `KeyRecordFirmwareIntegrationProbe`，新增第三个参数 `<synthetic-definition.xz>`，只使用模拟 endpoint、内存密钥和专用临时存储；完整命令和官方方法参见此前[离线记录](BACKEND_OFFLINE_INTEGRATION_20261013.md)。本批定义夹具为 `/private/tmp/keyrecord-hid-definition.xz`，其 base64 在 `/private/tmp/keyrecord-hid-definition.b64`；原始文件 `/private/tmp/keyrecord-vial-official-original-opaque.vil`，产物 `/private/tmp/keyrecord-hid-delivery-patched.vil`。这些材料均为合成数据。

主会话按 review-work/debugging 方法检查目标、源端口、协议字节、并发/取消、C ABI/资源边界、坐标来源、隐私、公开驱动和旧事务。修复了 IOHID 指针的实际 Swift 类型、DispatchWorkItem 的线程安全取消包装、UInt32 毫秒转换，以及合法空 KLE 属性误拒绝；实际编译和相关测试通过，没有放宽断言或抑制错误。没有未解决的范围内可行动问题。最终提交的自审/运行审计记录为 `/private/tmp/keyrecord-hid-review.md`。

## 后置真实证据

实际 IOHID 原生打开/发送/输入/取消和缓冲释放在本批仅有源码与编译证据，未连接设备执行；离线报告端口不能替代这些证据。没有枚举设备、真实 HID 读写、捕获、卸载、用户数据/Keychain 删除或签名发布。正式 App 仍不打开 HID，生产支持目录为空；不把新的格式标识、独立定义读取或模拟报告升级为生产资格。

仍需真实设备的报告描述符、权限、发送/取消时序、回包与固件效果，完整版本/键码矩阵、复杂定义/编码器/动态子协议及 VIA 设备/GUI 往返。Vial 的无编号响应不能排除成功交换之后任意设备重复包或同 UID 固件动态变化，分块键图也不是原子快照；真实验证需静止配置。完整 G2/G3/G4 与 v1 未合格。本批 CI 运行包测试和 App 构建，不执行原生窗口或真实设备用例。
