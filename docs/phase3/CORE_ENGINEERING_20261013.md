# Phase 3 事务与原生流程工程增量

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。功能开发已暂停，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

日期：2026-10-13，Asia/Shanghai。源码提交：`12be434e0f06343b3da9111b5b5d8d25d288716c`，从 PR23 合并提交 `3546b481974e3f819057fc6a0e15173a71bf520a` 开始。

本增量完成 Karabiner 核心事务路径的离线实现和产品组件接线。**实际部署适配器尚未接入默认产品会话，产品仍为配置副本预览/导出；本记录不宣称完整 Phase 3、G3 或稳定后端已合格。** 真实支持版本矩阵、重载、停用延迟和实际配置/设备证据按用户要求集中后置。完整卸载的固件恢复、登录项和本地数据串联仍待后续工程，本批仅完成安全移除受管规则的后端步骤。

## 已实现路径

`KeyRecordMappings` 提供映射草稿、结构化 diff、配置端口、加密事务存储和协调器。草稿包含稳定 UUID、名称、单个 Profile、触发/输出、全局或单一应用、全部键盘或明确的厂商/产品身份。生成支持严格的基本规则子集；不支持的动作不生成。阶段 B 的候选和手动候选均可创建草稿，设置中先选择方式和 Profile，再调整范围、检查、确认及导出/应用；切换后端保留 Karabiner 草稿。

Profile 使用完整、唯一名称定位，显示名称截短不会改变写入身份；重复名称拒绝。一个事务协调器只管理一个目标 Profile，切换前必须明确移除旧受管块或停止管理，避免遗留仍受管而失去停用入口的规则。Profile 内一个连续受管块使用独立命名空间；区间外原始字节和用户规则顺序保留。缺少 complex_modifications/rules 时仅插入相应局部结构；重复 JSON 键、结构损坏、受管标记缺失/重复/逆序及块外命名空间混用均拒绝。

应用前重新读取配置、能力、版本、观测和批内/用户规则，检查输出端和触发端、应用/设备/Profile 交集、重叠、链式映射及环。警告需要针对当前准备结果的确认；恢复和外部重新应用也不能沿用旧结果的确认。缺失证据仍明确列出，菜单未读取，未发现冲突不等于无冲突。未知版本及默认未连接适配器只能预览/导出。离线 temporaryConfiguration 只允许真实文件写入临时目录；没有填入任何生产支持版本或通过 UI 勾选建立支持资格。

每批先将前镜像及恢复元数据写入已有加密 ObjectStore，再写持久日志，然后执行同目录 write/fsync/rename/目录 fsync 和读回。保留 PRD K3/K12/K13 原有的文件摘要边界；没有新增能力 hash、冻结 contract、baseline 或发布 gate。普通输入与准备结果直接按模型值比较。共享 AtomicFileSystem 仅增加重命名前回调，原有原子替换与故障边界保留；临时文件完成后再次检查文件与运行上下文。

读回异常与启动对账按当前文件三分类：等于本产品写入结果则完成收尾；等于前镜像则标记未落盘、不重写；其他内容标记外部变更、拒绝自动写入。用户回滚只在文件仍等于本批写入结果时恢复前镜像，并恢复上一批管理意图。每批一份加密备份，滚动保留十份；删除计划先持久化，清理可重入；写日志前中断留下的备份只按该命名空间清理。

外部变更提供采纳、重新应用、停止管理三选一。采纳仅支持可安全规范化的基本受管规则，保留已知临时规则 ID 的临时属性；无法规范化或 ID 重复时拒绝，保留外部文件。重新应用针对当前文件重新准备、检查和确认；停止管理保留文件，不等同停用。停用以同一路径置空受管块并加密保留恢复意图；恢复重新检查。卸载准备的受管规则移除包括标记清理。接入部署会话时先执行对账；临时规则在安全对账后清理，外部修改仍优先拒绝自动覆盖。

原生组件展示草稿、范围、设备身份、diff、警告、状态和配置验证时间/来源。配置读回验证不证明应用效果。菜单栏增加停用入口，当前默认未接入写入适配器时不可用。副本读取沿用原有普通文件、拒绝符号链接、非阻塞、有界 JSON、监测、隐私 generation 和安全作用域释放；会话结束清除原始字节、草稿及准备结果，晚到读取/发布不能重开保护。导出只有映射规则，不含统计；文件为用户选择的明文边界，待写出凭据可撤销。

规则表达依据：[官方配置结构](https://karabiner-elements.pqrs.org/docs/json/root-data-structure/)、[修饰键语义](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/from/modifiers/)及[设备条件](https://karabiner-elements.pqrs.org/docs/json/complex-modifications-manipulator-definition/conditions/device/)。这些文档不构成本机支持版本证据。

## 验证与自审

主会话完成真实临时文件、加密对象存储、公共入口驱动和原生 NSHostingView/辅助功能按钮验证。不同用例的最终通过结果按受影响范围复用；没有重复 Phase 1 网络观察或实机验收。总计 **62 项不同的相关场景最终通过：45 项 SwiftPM、17 项 App**。未签名 arm64 App build-for-testing 通过。

| 场景 | 观察与证据 |
|---|---|
| Profile/受管块/diff、应用/设备交集、能力/版本变化、链与环、警告确认 | 12 项映射协调场景；`/private/tmp/keyrecord-p3-audit-final.log`、`keyrecord-p3-final-mapping.log`，采纳相关最终覆盖见 `keyrecord-p3-adoption-final.log` |
| 真实文件、加密落盘/重开、十份备份、隐私代次、符号链接/FIFO/硬链接、临时写入中外部编辑 | 4 项文件场景；`/private/tmp/keyrecord-p3-audit-final.log` |
| 四个原子写入边界真实 SIGKILL 后从磁盘重开 | 四个子场景覆盖 afterWrite、afterFileFsync、afterRename、afterDirectoryFsync；重开对账不改写当前配置，包含于上述文件场景 |
| 相邻分析与规则解析 | 13 项；`/private/tmp/keyrecord-p3-audit-final.log` |
| 原有序列化、导入依赖和共享原子替换边界 | 4 项序列化、6 项模块边界、4 项共享 crash probe、2 项 fenced persistence；`keyrecord-p3-audit-final.log`、`keyrecord-p3-regression.log` 中未受影响通过项及 `keyrecord-p3-boundaries-final.log` 中两项最终修正结果 |
| 原生草稿保留、输入变更、隐私撤回、长 Profile 身份、双语和实际按钮 | 5 项；精确源码提交 QA 为 `/private/tmp/keyrecord-p3-native-12be434e.log`；双语截图在 `/private/tmp/keyrecord-p3-native-final-qa/` |
| 原有副本导入、晚到请求、文件保护、双语参考 | 10 项；`/private/tmp/keyrecord-p3-import-regression.log` |
| 双语目录与 Xcode 产品图 | 各 1 项；`/private/tmp/keyrecord-p3-localization.log`、`keyrecord-p3-app-graph-final.log` |
| 公共入口手工运行 | `KeyRecordMappingCrashProbe --help`、`--offline-run`、无效参数退出 2；正常路径实际应用、配置验证、停用、恢复、拒绝外部回滚、采纳与移除规则；`/private/tmp/keyrecord-p3-driver.log`、`keyrecord-p3-driver-invalid.log` |

失败记录保留：早期目标未建立测试目录、timespec 比较、digest 名称遮蔽、非 Sendable 主线程回调均曾编译失败，修正后构建通过。原有序列化类型、SwiftPM 图/导入和 Xcode 产品图的登记检查曾失败；精确登记后通过，没有删除或放宽原有测试。截图曾显示错误的全局作用域键名，已修正。状态键拼接被原有本地化审计识别为静态残缺键，按既有插值方式修复。自审反例明确复现采纳后丢失临时属性（同一用例三处失败），按 ID 保留属性后同一用例通过；失败与修复日志为 `/private/tmp/keyrecord-p3-adopt-temporary-before.log`、`keyrecord-p3-adopt-temporary-after.log`。

自审按 review-work 和 debugging 的 Codex 主会话规则执行，没有冒充独立审查或真实后端验收。

| Lane | Exact source commit | Verdict | Report / artifact |
|---|---|---|---|
| Main-session manual QA | `12be434e0f06343b3da9111b5b5d8d25d288716c` | PASS，限本增量离线范围 | 本表；`/private/tmp/keyrecord-p3-native-12be434e.log`、最终驱动和场景日志 |
| Main-session self-review / runtime audit | `12be434e0f06343b3da9111b5b5d8d25d288716c` | PASS，限本增量离线范围 | 本记录的范围、失败/修复、证据和以下限制 |

主目录仍为 `64590a0e9` 和 215 项历史/其他改动；仅隔离 worktree 开发。临时证据可能随清理过期，不能保证长期存在。

## 尚未完成的范围与继续推进

没有读取日常配置、查询真实键盘、安装/调用实际 Karabiner、写系统映射、启动真实采集、操作日常钥匙串或公开发行。实际适配器连接、真实支持矩阵、配置 schema 接受度、重载/效果、真实并发编辑及 ≤2 秒 p95 停用仍无合格证据。最后重检加原子替换是原有乐观并发路径，不能宣称拥有跨进程文件 CAS 或已排除所有真实编辑竞态。

以下工程继续自主推进，不等待一次重复试用：补齐正式部署会话的授权/目标绑定/生命周期及可注入版本读取接线，保持生产支持矩阵为空时只读；完成完整卸载准备串联；再推进 Phase 4 固件安全修补/导出与跨对象日志。实际后端资格与真实验证集中到稳定候选后一次处理，未知版本不因离线通过而放行。完整 G3、G4、FR-P6 和公开发布仍保留原有要求。
