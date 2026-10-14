# 恢复副本覆盖必须在移除规则前发现

## 实际复现

基于 main `d34ffbbb7b80db90d0b82a94c33ad0dcad48b656`，在临时加密存储中保留两个内容不同的原始固件副本，再通过公开 `UninstallPreparationCoordinator.prepare` 将它们导出至同一文件。卸载端口全部替换为记录调用顺序的回调。

| 场景 | 修复前 | 修复后 |
| --- | --- | --- |
| 同一文件，不删除本地数据 | 第一个导出被覆盖，却返回 `ready`；调用移除规则和登录项 | 报 `externalChange`，仅执行停止捕获回调 |
| 同一文件，删除本地数据 | 移除规则和登录项后才报错；磁盘上已有错误的 `ready` 记录 | 报 `externalChange`，仅执行停止捕获回调 |
| 两个不同文件，不删除本地数据 | 两份文件正确，返回 `ready` | 保持正常 |
| 两个不同文件，删除本地数据 | 两份文件正确，返回 `completed` | 保持正常 |

根因是逐份导出后的立即回读只能证明当时的单个文件正确。后续导出可以覆盖前一份，而流程在宣告 `recoverySecured` 前仅比较了加密记录列表，没有核验最终的一组外部恢复文件。

## 修复范围

提取已有删除前的“记录列表不变 + 每份导出与保留原文逐字节相同”核验为 `verifyRecovery`，在所有导出完成后、写入 `recoverySecured` 及移除规则之前执行一次。原来的删除前调用位置完整保留。每次读取恢复目的文件前再检查当前授权。

不新增 hash、冻结 contract、baseline 或持久化格式。这里修复的是已有卸载边界的错误成功结论，实际读取最终导出文件，不用路径字符串预检查代替文件验证。两个内容完全相同的原始副本可共用同一文件；不同内容通过同名或等价路径互相覆盖时会被发现。

覆盖已经发生的外部导出文件不会自动回滚；两份加密原始副本保留，用户可改选不同文件重试。修复不把恢复文件变成持续受监控的对象，也不声称消除最终检查之后的同用户外部改写竞态。

## 验证

- 公开 API 的同一临时程序实际执行四种场景，保存修复前后日志。没有调用真实捕获停止、规则移除、登录项或数据擦除实现。
- 失败先行：两个新增包测试在旧产品代码上有 14 个失败断言。直接同路径和含 `..` 的等价路径，在两种删除选项下均复现；不同路径的重试及相同原文共用文件仍应成功。最初符号链接父目录夹具被 macOS 安全书签提前拒绝，改用可实际执行的等价目录路径后记录正式失败证据。
- 包测试检查调用顺序、进度阶段、无新准备记录、加密原文保留、拒绝后的同实例重试及相同原文兼容。原有“移除规则期间恢复文件变化时，删除前拒绝擦除”的测试继续执行。
- App 专项测试覆盖两种删除选项：碰撞不显示卸载就绪、不调用移除端口、退出忙碌和维护状态；重新选择不同文件后恢复正常。其余原生映射流程作为回归执行。

复现和回归命令：

```sh
swift run --package-path /private/tmp/keyrecord-to-public RecoveryDiscovery
swift test --filter 'KeyRecordMappingsTests|ProductBoundaryTests'
```

公开驱动源码为 `/private/tmp/keyrecord-to-public/Sources/RecoveryDiscovery/main.swift`。日志为 `/private/tmp/keyrecord-recovery-before.log`、`/private/tmp/keyrecord-recovery-red-final.log`、`/private/tmp/keyrecord-recovery-after.log`、`/private/tmp/keyrecord-recovery-tests.log`；未签名构建和原生回归日志为 `/private/tmp/keyrecord-recovery-xcode.log`、`/private/tmp/keyrecord-recovery-native.log`。PR、push、main CI 结果分别以 GitHub 对应提交的运行记录为准。

## 后置验证边界

全部文件、密钥和回调均为临时合成夹具；本轮不执行真实卸载、配置修改、设备 HID、Keychain、签名或公证。生产支持目录与真实连接默认值不变。真实设备、真实卸载和正式发布资格继续后置，离线通过不能替代 G2/G3/G4 或完整 v1 验收。
