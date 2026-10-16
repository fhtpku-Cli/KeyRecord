# VIA 层与修饰键组合入口保护

基于 main `29f855d5c043757956e6e736d5675124f370eed0`，继续用户主动导出和导入 VIA 配置文件的流程。

## 复现与官方对照

官方 VIA `LM(layer, modifiers)` 表示层与修饰键组合入口，例如 `LM(1,MOD_LCTL)`、`LM(2,MOD_LSFT | MOD_LALT)`。先前 Vial 专用保护已识别 LM，但 VIA 共用保护遗漏了这一族。在注入离线兼容条目的测试中，手动修改可将入口替换为普通字母，并产生预览、导出文件及待导入事务。扩充既有两项回归后，修复前实际出现 12 个断言失败，日志为 `/private/tmp/keyrecord-via-lm-red.log`。

扩充已有官方执行脚本，直接调用 VIA 的字典选择、导出和导入转换函数，在协议参数 7、10、11、12、13 下验证上述两个 LM 表示，新增 10 个往返场景。沿用已有源码版本：[advanced-keys.ts](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/utils/advanced-keys.ts)。协议 13 仍使用合成键码版本参数 0，仅确认这版官方代码的选择行为，不证明真实运行实例。

## 修复与自审

将 `LM(` 加入现有保护前缀，在手动／自动修改和实际字节修改前拒绝覆盖；不增加 LM 解析器，不扩展输出白名单，也不凭 LM 推导额外可达层。相邻普通按键仍可修改，原入口保持不变。拒绝时不生成预览或导出文件，加密原件及事务状态保持原样。

自审核对原有 Fn、其他层入口及 Vial 保护不变，自动空位检查没有被替代。既有官方 CI 入口继续执行全部原有场景，VIA 层入口转换场景由 10 个扩展为 20 个。没有增加 hash、冻结 contract、baseline 或 gate。

本地验证通过：30 项固件事务测试、完整 794 项 package 测试、100 项原生测试、Debug 测试构建及 20 个官方层入口转换场景。日志为 `/private/tmp/keyrecord-via-lm-green.log`、`/private/tmp/keyrecord-via-lm-package.log`、`/private/tmp/keyrecord-via-lm-native.log`、`/private/tmp/keyrecord-via-lm-oracle.log`。

生产支持目录仍为空，复现依赖测试注入的兼容条目，不代表生产环境已允许修改或真实键盘兼容。真实 HID、Keychain 恢复、卸载及发布验证继续后置，保留删除前复核。
