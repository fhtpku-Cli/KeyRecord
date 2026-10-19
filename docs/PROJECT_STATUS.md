# 当前项目状态

核对日期：2026-10-20（Asia/Shanghai）。**按用户要求暂停功能开发，当前只整理仓库及项目文档。** 不自动启动第八批，不恢复定时续轮或浏览器实例绑定。恢复开发与真实验证另按用户后续指示执行。

## 仓库与交付依据

- 本次文档核对的产品代码为远端 main 的 `4fba3370fb2ef1353b523e3a401bbcc36fcce8c3`，即 [PR #73](https://github.com/fhtpku-Cli/KeyRecord/pull/73) 的合并提交。
- 第七批最终分支提交 `fe6bd6c1642b7358296dd9fab55dbfb2d49c4421` 的 [push CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/39277976555) 和 [PR CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/39278030535) 均成功。合并提交的 [main CI](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/39309800836) 成功；该次通过现有 `workflow_dispatch` 手动触发，不能记成自动 push 运行。
- 核对开始时没有未合并 PR。文档整理自身的提交和 CI 另以对应 PR 为准，不把产品测试记录重新命名为文档验收。
- 主目录 `/Users/bytedance/Documents/KeyRecord` 仍停在旧的 `64590a0e9`，含用户未提交代码、文档与本地证据。它不是最新 main，本轮保持只读，未重置、清理或搬入这些改动。编辑使用已附加的干净隔离工作树。

## 当前能做什么

| 范围 | 已完成工程 | 当前边界 |
|---|---|---|
| Phase 1：采集、隐私与加密存储 | 已批准的 Apple Silicon MVP 已完成限定候选的实测与合并 | 历史实测为 arm64 macOS 27.0 build 26A428；不覆盖当前所有变更、所有平台或公开发行 |
| Phase 2：统计与推荐 | A/B 离线工程、能力过滤、冲突说明、特殊键池、手动候选及推荐到后端草稿已接通 | 完整 G2 真实产品链路证据未齐；逻辑排名保持独立，不将参考布局当真实物理收益 |
| Phase 3：Karabiner | 事务写入/读回、备份/回滚、外部变更处理、部署会话、卸载准备及应用行为测试清理流程已实现 | 生产版本/Profile 支持表为空；真实重载、应用效果及紧急停用延迟未合格 |
| Phase 4：VIA 文件工作流 | 用户导出最新配置 → KeyRecord 保留原件、选实际层/位置与基础输出键、预览并导出 → 用户手动导回 VIA | 文件兼容依据只允许现有 90 个基础输出键；不生成组合快捷键、应用专属规则或高级动作，不证明设备/导入器的真实资格 |
| Phase 4：Vial | 独立定义、矩阵、编码器、四类动态条目、宏、布局选项、QMK 设置的协议读取与离线比对已实现，设备选择与读取工厂已接入产品 | 设备支持目录为空；未知表示保持部分验证。没有真实 HID、断连或键盘效果资格，不生成高级配置 |
| 物理按键依据 | VIA 文件/定义、Karabiner Profile、系统键盘服务及属性、USB 型号对应、Vial 自身简单几何快照已接通；变化和隐私撤销处理已实现 | 型号匹配不是设备归属证明；缺少完整变换链时整对回退逻辑按键数。Vial 快照不是实时活动层/映射 |
| 完整密码备份 | 全部已保存对象独立密码加密；只恢复到空资料库，以新的本地密钥封装，恢复后保持暂停且不自动应用映射 | 真实 Keychain 恢复、Intel KDF 计时及发布验证后置；不覆盖已有资料库，删除前复核保留 |

当前源码采用原生 arm64 macOS 27 及以后系统的锁屏状态来源，锁屏状态为锁定或未知时停止采集；这项运行策略不等于所有后续系统均已实测。最低编译目标 macOS 14+、未签名 Universal 构建与正式运行支持范围也不是同一概念。

## 最近七批实际交付

| 批次 | 已合并 PR | 结果与详细记录 |
|---|---|---|
| 一 | [#67](https://github.com/fhtpku-Cli/KeyRecord/pull/67) | [VIA 文件改键入口](phase4/VIA_GUIDED_FILE_EDITING_20261019.md)：实际文件槽位与具名按键选择、预览导出及手动导入指引 |
| 二 | [#68](https://github.com/fhtpku-Cli/KeyRecord/pull/68) | [Karabiner 行为测试](phase3/BEHAVIOR_SESSION_20261019.md)：开始、结果、取消、失败、正常退出和异常重开清理 |
| 三 | [#69](https://github.com/fhtpku-Cli/KeyRecord/pull/69) | [推荐到后端草稿](phase4/RECOMMENDATION_HANDOFF_20261019.md)：保留组合/应用原意，固件只接可表达的全局基础改键 |
| 四 | [#70](https://github.com/fhtpku-Cli/KeyRecord/pull/70) | [物理来源会话](phase2/PHYSICAL_SOURCES_20261019.md)：来源明细、变更撤销、迟到结果拒绝和逻辑回退 |
| 五 | [#71](https://github.com/fhtpku-Cli/KeyRecord/pull/71) | [实际来源适配器](phase2/PHYSICAL_ADAPTERS_20261019.md)：系统属性、Karabiner 主配置及 Vial 读回参考 |
| 六 | [#72](https://github.com/fhtpku-Cli/KeyRecord/pull/72) | [设备与布局对应](phase2/DEVICE_LAYOUT_20261019.md)：唯一 USB 型号参考、歧义及身份失效处理 |
| 七 | [#73](https://github.com/fhtpku-Cli/KeyRecord/pull/73) | [Vial 自身定义几何](phase2/VIAL_LAYOUT_20261019.md)：两次定义读取一致性、逐层位置对应、失效后必须重新读回 |

上述增量主要使用模拟端口、临时配置、加密测试资料库及离线官方方法验证。第七批本地全量包测试 828 项、原生离线回归 130 项及构建通过，自审后的相关测试复验通过；数量属于该提交，不要求未来保持相同数量，也不代表执行了全部实机/UI 测试。

## 尚未完成的工作

**可继续研究或离线实现，但现已暂停：** 非 USB 身份与歧义处理、复杂/动态布局及选项的明确表达、固件活动层/时序、软件实际启用与执行顺序、其他软件/macOS 变换来源。每项先说明来源能证明什么，再模拟采集、变化及拒绝路径，不能靠更多模拟对象补出真实来源资格。

**需要产品决定：** 现有聚合不记录逐事件设备归属和时序，不能回溯恢复历史物理动作。是否扩展未来统计的数据范围、隐私说明及多设备语义，需要单独确定；不能直接以“补适配器”名义增加采集。当前配置估算与历史动作还原必须分开。

**必须真实验证：** Karabiner 真实重载/应用行为/停用 p95，VIA 官方 GUI 导入及键盘效果，Vial 实际 HID/断连/读回/设备覆盖，密码备份的真实 Keychain 恢复，包含恢复副本的真实卸载，以及完整平台、签名、公证和发布验证。已有 Phase 1 限定实测无需全部重做，但也不能自动覆盖新流程。

## 文档入口

[路线图](ROADMAP.md)记录暂停点与恢复工作顺序；[文档索引](STATUS_INDEX.md)覆盖全部受版本控制的 Markdown；[需求](PRD.md)与[架构](TECHNICAL_ARCHITECTURE.md)区分目标和实现。[历史状态](PROJECT_HISTORY.md)、[历史路线图](ROADMAP_HISTORY.md)及日期记录保留当时结论，不作为当前待办。[本次核对记录](DOCUMENTATION_REVIEW_20261020.md)列出整理范围与检查。
