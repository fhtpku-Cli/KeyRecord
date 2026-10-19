# VIA 文件中的 Fn 层入口保护

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

基于 main `3fa6fc2cd80cd9bc0119742fc706cc9d1a7718bf`。

## 失败场景和官方来源

VIA 配置中的 `FN_MO13` 和 `FN_MO23` 是层入口：分别保持层 1、层 2，两者配合可进入层 3。原来的通用保护列表只覆盖 `MO(...)` 等表达式，Vial 6 的专用保护没有覆盖 VIA 文件路径。因此，在注入离线兼容条目的测试中，手动改键可以将这些入口替换成 `KC_A`，成功预览并导出。

两项新增 Swift 测试实际执行了补丁与加密事务，修复前出现 12 个断言失败；包括手动覆盖成功、生成输出文件、事务进入待导入状态，以及自动修改没有按层入口分类拒绝。日志：`/private/tmp/keyrecord-via-fn-red.log`。生产支持目录为空，所以本复现不代表当前生产环境已经允许该导出，更不代表真实键盘验证。

官方来源沿用现有 CI 检出的 VIA app 版本：[键码转换与层菜单](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/utils/key.ts)、[字典选择](https://github.com/the-via/app/blob/935106a990af39bdd1ade881c02366eac486240d/src/utils/key-to-byte/dictionary-store.ts)。新增脚本实际加载官方 TypeScript 模块，执行 `getBasicKeyDict`、`getByteToKey`、`getCodeForByte` 和 `getByteForCode`。协议参数 7、10、11、12、13 下，两种名称均完成导出／导入转换往返，共 10 个场景；协议 13 使用合成键码版本参数 0，仅验证这版官方实现的选择行为。

## 修复和离线回归

将这两个精确名称加入已有入口保护列表，不扩大允许输出、不推导新的层可达性、不改写原始文件。回归覆盖手动／自动拒绝、相邻普通键仍可修改、原入口保留，以及拒绝时无预览产物、无导出文件、事务与加密原件不变。

`Scripts/via-keycode-oracle.cjs` 已接入现有 `verify-firmware-oracles.py`，和原有官方夹具及加密往返一起由 push、PR 和 main CI 执行。没有新增来源 hash、冻结 contract、baseline 或门禁机制。

自审核对保护发生在自动空位判断和实际字节修改之前，已有 Vial 保护保持有效，官方模块实际执行且未用本地模拟实现替代。真实设备 HID、真实 Keychain 恢复、真实卸载与发布验证继续后置，删除前复核保留。

本地验证通过：30 项固件事务测试、全部 794 项 package 测试、100 项原生测试、Debug 测试构建，以及完整官方回归入口（11 份夹具、10 个来源选择场景、10 个 VIA Fn 转换往返、9 类加密事务往返）。日志位于 `/private/tmp/keyrecord-via-fn-green.log`、`/private/tmp/keyrecord-via-fn-package.log`、`/private/tmp/keyrecord-via-fn-native.log`、`/private/tmp/keyrecord-via-fn-oracles.log`。
