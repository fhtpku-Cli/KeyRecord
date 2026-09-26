# 暂停资源与隐私关闭：给执行者的测试方案

当前状态见 [PROJECT_STATUS.md](PROJECT_STATUS.md)。PR #9/#10 已合并；
`64590a0e9b57a55af9a23921983f2c16bb59c62e` 的单页安全输入回归见
[专门记录](PR10_SINGLEPAGE_REGRESSION.md)。下方旧结果各自绑定历史候选，不是当前性能验收。

## 当前 Debug 试验隔离

同时配置 `KEYRECORD_TRIAL_STORE`（私有临时目录）和 `KEYRECORD_TRIAL_NAMESPACE`
（专用测试条目命名空间）；不完整、非法或与生产目录重叠必须拒绝启动，不回退真实数据。
每轮摘要和日记使用新路径，正常退出后保留证据，下一轮不得覆盖。

对于当前使用传统文件钥匙串的 `LocalKeychainBackend`，不要覆盖 `HOME` 或
`CFFIXED_USER_HOME`。本轮实测临时 HOME 下默认钥匙串定位失败，点击同意出现
“找不到用于储存 master-v1 的钥匙串”；正常用户环境的只读定位成功。
应取消该系统对话框、正常退出，修正启动环境，不点击“还原为默认”，不重置用户钥匙串。

专用 namespace 隔离 service/account 条目，不是独立钥匙串文件，也不授权删除已有条目。
显式 trial store 隔离统计数据；只去掉 HOME 覆盖而不配置 trial store 是错误操作。
试验库、密钥和用户截图不放进公共证据；保留无输入内容的计数摘录和可复现步骤。

## 可复用能力

- 结束摘要：Debug 进程在正常退出时，若设置了 `KEYRECORD_DIAGNOSTIC_SUMMARY_PATH`，写入累计计数。它包含全程合计及缓存状态；退出时通用 `captureSessionLive` 可能陈旧，需结合 Quit 的 `sessionLiveAfter`、摘要和进程退出核对。
- 分层计数：tap、handoff、normalization、aggregate、flush 的 issued/durable/failed/timeout/returned/succeeded/invalidated。`flushInvalidated` 表示迟到写回被作废。
- 发布计数：`snapshotPublicationCount` 是模型发布，不是屏幕像素。
- 暂停隐私监视：暂停且统计仍可见时，约每 250ms 复查；条件不明或不可用则关闭受保护状态，不自动恢复采集。
- 资源采样：`KeyRecordResourceSampler` 用 `proc_pid_rusage` 的 `ri_phys_footprint`。不读 RSS，不把 RSS 当成物理占用。

## 观测缺口与本轮诊断

结束摘要无法把增量切到“关闭区间”。截图前后总数相同也不能证明关闭期间没有采集。

间隔日记 `KEYRECORD_PRIVACY_INTERVAL_PATH` 只在 Debug 且路径已设置时写文件。未设置路径时不写。

- `change`：粗状态变化才写。`currentLockState` 只在这一行自己读过锁时才有值；没有读过就是空，状态是 `notChecked`。不要把缓存的 unlocked 当成这次观察。缓存值另记在 `cachedLockState` / `cachedSecureInputState`。blocked 阶段不接收条件更新，缓存可能一直是 unlocked。
- `begin`：隐私关闭撤销完成后写，`boundaryCause=protectedStateClosed`。启动时本来就隐藏的状态记为 `closedStateObserved`，评估器默认不评估它。
- `end`：在重新开放的那一步之前写。`captureSessionStarting` 是新采集会话能接收事件之前；`protectedDisplayReauthorized` 是重新读取受保护统计之前。`sessionObservedLiveWithoutBoundary`、`visibleWithoutReadBoundary` 表示没有在正确位置记到边界，评估为 `inconclusive`。
- `observe`：关闭期间约每秒一次，读锁屏和安全输入，并附 `lockComponents`（会话字段、控制台标志、是否收到锁/解锁通知，均为粗状态）。
- `actionBegin` / `actionEnd`：Start、Resume、Accept、Quit 进入时和返回时各写一行，同一个 `actionSeq`。只有 begin 没有 end：已进入未完成。两者都没有：未进入（前提是日记没写失败）。`actionDetail` 里的值都取自真正参与决策的那次读取：`prepareLockRead`、`prepareOutcome`、`permissionStatus`、`lifecycleCommandRun`、`abortRun`、`readinessOutcome`（生命周期 readiness 实际返回值）、`phaseAfter`、`failureAfter`。Quit 另有 `invocation`（menu / applicationShouldTerminate）、`lifecycleFlushCalls` / `lifecycleFlushOutcome`（真正执行的 flush 次数和结果）、前后未保存标记、`quitDecision`、`noticeAfter`。
- `witness`：只有设置了 `KEYRECORD_SYSTEM_WITNESS_SECONDS`（1–300）且日记已启用时才写，每秒一次，到时自动停止，每次启动只开一个窗口。它在任何阶段都读，包括采集中，所以不依赖产品是否关闭。只读锁屏和安全输入的粗状态，不读密码、按键或受保护统计。
- `privacyTrigger` 是关闭调用点的名字。生命周期里的 `blockedReason` 仍可能是 `sessionLocked`，不能只用这个标签判断真的锁屏。
- `lockReadStatus` / `secureInputReadStatus`：`notChecked`、`unknown`、`locked`/`unlocked`、`enabled`/`disabled`。`notChecked` 不是安全。`unknown` 也不是安全。
- 计数是逐项拷贝，不是原子快照。写入串行化，文件顺序与 `seq` 一致。写文件失败时 `privacyJournalWriteFailed` 为真（也写进结束摘要），评估结果是 `invalid`。缺 begin 或 observe 是 `inconclusive`，缺 end 是 `interval-not-ended`。关闭段里只增加了 `handoffAccepted`、其他输入计数不变时是 `inconclusive`（可能是边界前的在途事件）。`flushInvalidated` 记为边界前在途写回被作废，不算关闭期间的新输入。关闭期间成功的受保护读取、发布或 durable 确认都算异常。有限的 observe 不能证明每个时刻都关闭。

当前 Debug 采集路径由 `secureInputMonitor` 约每 250 ms 复查安全输入；enabled/unknown 关闭采集和受保护展示，恢复需新鲜的安全条件与既有采集意图。250 ms 是轮询间隔，不是严格最大响应时间。仍需独立 `witness` 确认 enabled，不能只用产品是否关闭或密码框外观判断。

`ProductReduction.snapshot/analysis` 在 Debug 增加尝试/拒绝计数。它们只覆盖这条展示读取路径，不能证明存储层每一次 `readProtected`。

间隔日记能证明：两条相邻记录之间，计数差发生在前一条记录的粗状态期间。它不能证明：渲染、两次记录之间被漏掉的状态、存储层全部读取、采样间隙里的内存尖峰。

## 资源口径

采样间隔：探索 0.2–1 秒；暂停候选与正式窗口用 1 秒。预热样本不进入 CPU 和足迹统计。

CPU = 100 × 目标进程自身 user+system 纳秒增量 / 1e9 / `CLOCK_MONOTONIC` 秒增量，单逻辑核。不含采样进程，不含子进程。子进程 CPU 单独报告；若不为 0，`productProcessOnly=false`。

物理占用：测量窗口内 `ri_phys_footprint` 的算术平均和采样峰值。采样峰值不是采样间隙的上限。

有效性：进程退出、PID 启动时间或路径变化、控制台用户 UID 变化或消失、`CLOCK_MONOTONIC` 比 `CLOCK_UPTIME_RAW` 多跳过 0.5 秒（休眠）、样本失败或间隔超过 2.5 倍，结果为 `interrupted` 或 `invalid`。不输出产品通过。不调用阻止休眠的接口。

协议：

| 协议 | 时长 | 结果含义 |
| --- | --- | --- |
| `exploratory` | 调用者指定的短窗口 | 只说明工具跑通，不是验收 |
| `pausedMonitorCandidate` | 预热 60 秒，测量 600 秒 | 暂停监视开销的候选测量，不是 FR-S2 |
| `formalFRS2` | 每个窗口预热 60 秒、测量 600 秒；打字与空闲各 3 次 | 短于该时长会被拒绝。单机结果仍不能代替 Intel 或其他系统版本 |

入口：

```sh
swift build --product KeyRecordResourceSampler
bash Scripts/measure-process-resources.sh \
  --pid <已存在的测试进程> --expect-path <该进程可执行文件> \
  --protocol exploratory --phase paused \
  --warmup-seconds 1 --measure-seconds 2 --interval-seconds 0.5 \
  --output <私有json>
```

脚本不启动 KeyRecord。

## 实机场景（先取得用户批准，再开始）

候选版本必须从本分支重新构建的 Debug，开发签名，单独目录运行。不要替换用户正在用的 App，不要用 Release 采集。数据只用临时测试目录和临时钥匙串命名空间；不要打开、复制或解密用户真实统计库。

每个场景使用新的摘要路径和间隔日记路径。正常结束用菜单退出。强制杀死没有摘要，不能当成保存成功。休眠、会话变化或样本缺失时保留中断结果，不补记为通过。

### 1. 暂停资源

问题：用户已暂停时，产品进程的 CPU 和物理占用是多少。

前置：用户已暂停，菜单可见，本场景不再输入。预计：候选协议约 11 分钟；探索性短测约 1 分钟，且不能代替候选协议。

操作：用户确认暂停后不要操作键盘。执行者只对已经在跑的测试进程采样。

预期：`outcome=measured`，`qualification=not-a-product-pass`，`rssUsedAsFootprint=false`。失败：进程退出、路径不符、出现采集计数增加。无法下结论：休眠、会话变化、缺样本、子进程 CPU 不为 0、只用了短测。

需要批准：启动该 Debug 候选、对它采样 11 分钟。

### 2. 锁屏关闭与恢复

问题：锁屏后采集、受保护展示读取和统计展示是否停住；解锁后是否重新检查，且用户暂停时不自动恢复采集。

前置：先在允许的普通文本里产生少量已知计数，然后暂停或保持采集，二者要分成两次运行，不要混在一次里。预计：锁屏保持 30–60 秒，加上前后各一次明确输入。

操作：用户自己锁屏和解锁。执行者不锁屏、不唤醒、不输入密码。解锁后先看间隔日记，再决定是否按菜单“继续”。若本次开始前是暂停，解锁后不要点继续。

预期：关闭状态那一段的 `aggregateDelta`、`handoffAccepted`、`normalizationOutput` 为 0；展示读取要么停止，要么拒绝计数增加。暂停运行在解锁后 `captureSessionLive` 仍为 false。失败：关闭段计数增加，或暂停后自己变成采集。无法下结论：只有起止截图、日记缺失、中间没有两条关闭记录、或锁屏期间有人输入了非测试按键。

需要批准：锁屏、解锁，以及是否允许解锁后点“继续”。

### 3. 安全输入关闭与恢复

问题与锁屏相同，但触发条件是安全输入，不是锁屏。

操作采用 [单页无聊天流程](PRIVACY_RESOURCE_USER_STEPS.md#单页安全输入回归采集中)。执行者持续核对日记里的 `secureInputReadStatus`。只有它变成 `enabled` 之后，才把这一分钟算作安全输入关闭。不要把“出现了密码框”当成已经开启。不要输入真实密码，也不要记录窗口名称。保持 30–60 秒后关闭该框。不要和锁屏放在同一次运行。

预期：关闭段有 begin、至少一条 observe、以及 end，且 end 减 begin 的采集计数为 0。失败：关闭段计数增加。无法下结论：没有 `enabled` 读数、缺边界、写失败，或只有起止相同的总数。

需要批准：打开和关闭该密码框。

### 不做在本方案里的场景

权限变化、快速用户切换、网络抓包、Intel 正式性能、Release 真采集。它们各自需要单独批准。

## 已观察的旧结果

这些来自旧日记，不是本轮新工具的实机结果。机器是这一台，不是正式性能验收。

- 暂停候选测量：CPU 约 0.0187%（一个逻辑核），物理占用均值 19765328 字节，采样峰值 20202408 字节，598 个样本。`outcome=measured`，`qualification=not-a-product-pass`。
- 暂停时锁屏和密码框：没有自己恢复采集。关闭那一分钟没有第二条记录。
- 采集时锁屏：菜单 blocked，`blockedReason=sessionLocked`，采集关闭。解锁后 Start 没有离开 blocked。Quit 被取消，没有正常退出摘要。
- 采集时密码框：菜单一直 Collecting。没有独立确认安全输入已开启。
- 当时每行 `currentLockState` 都是 unlocked，包括 sessionLocked 那一行。那是缓存，不是当次读取。

## 已执行的离线验证

工作树 `.build/privacy-measure-evidence/`（不提交）：

- `swift test --filter 'ResourceEvaluationTests|CaptureDiagnosticCounterTests|PrivacySerializationTests'`：通过。资源评估 5 项、诊断计数 9 项、隐私序列化测试均无失败。
- `KeyRecordResourceSampler --self-check`：退出 0。合成进程物理占用均值 35324384 字节，`qualification=not-a-product-pass`。日志：`self-check.txt`。
- 正式协议若预热不是 60 秒或测量不是 600 秒，在采样前退出 2，输出 `formal-fr-s2 refuses short windows`。日志：`formal-short.txt`。

本轮没有启动 KeyRecord，没有签名。Release 检查见下。

`swift build -c release --target KeyRecordCore` 已完成。`CaptureDiagnostics.o` 和 `DebugTrialIsolation.o` 只有 Swift 强制加载桩，没有日记或试验目录符号。`KeyRecordCore.o` 的导出符号里没有这些名字。

`xcodebuild -scheme KeyRecordApp -configuration Release CODE_SIGNING_ALLOWED=NO` 成功。二进制是 DerivedData 里未签名的 `Release/KeyRecordApp.app`。`nm` 和 `strings` 都没有 `notePrivacyInterval`、`beginClosedInterval`、`diagnosticInputWitness`、`KEYRECORD_PRIVACY_INTERVAL_PATH`、`KEYRECORD_TRIAL_STORE`。这不能证明优化后的等价代码绝对不存在，也不能代替一次运行中的 Release 采集限制检查。Release 采集限制没有被解除。

日志：`.build/privacy-measure-evidence/release-core-nm.txt`、`release-app-scan.txt`。

这些日志只证明工具和合成夹具，不证明 KeyRecord 产品。

## 2026-09-26 复核与离线定位

证据目录 `.build/handoff-review-20260926/`（不提交）。接手时完整 `swift test` 有 3 项失败（新增测量 target 未登记到包边界测试），Debug App 编译失败（诊断代码把 `Notification` 送进主线程任务）；二者已修正，边界检查没有放宽。

`ProductRecoveryQuitTests` 在无宿主测试里用生产的组装代码构造产品：真实生命周期、恢复 fence、协调器、reducer、flush 调度器和临时目录中的加密存储；只替换钥匙串、tap、锁屏/安全输入/前台 provider、输入监控权限、登录项、锁屏通知和 `NSApp.terminate`。不启动真实采集，不读真实统计库或钥匙串。

- 已离线复现并修复：暂停后锁屏再解锁，点 Resume 进入 `failed`（`resumePersistenceFailed`），之后 Start 重试同一次失败的保存，只能重启恢复。根因：隐私关闭调用 `closeProtectedSession()`，`ProductPersistence.save()` 不像 `load()` 那样重新打开存储，直接抛 `storeNotInitialized`。修复：`save()` 在门控检查后先 `bootstrap()`。失败日志 `recovery-red.log`，通过日志 `recovery-green2.log`。
- 离线未复现：采集中锁屏 → 解锁 → Start 可以恢复采集；blocked 时 Quit 经菜单和 `applicationShouldTerminate` 两条路径都会退出；锁屏丢弃未保存增量、保留已持久化计数、不留下 dirty 标记；flush 真实失败时 Quit 取消并显示提示，恢复后可正常退出。实机现象的剩余假设见交付说明，需要一次实机诊断区分。

这只是离线验证，不是实机行为验证。

### 2026-09-26 实机诊断（用户批准）

证据 `.build/round2-evidence/`（不提交）：本工作树签名 Debug 构建，`source-changes.patch` 的 SHA-256 为 `05a3eb47…6170d`；隔离 store `.build/round2-trial/store`，命名空间 `com.keyrecord.trial.round2`；真实 store 目录修改时间前后一致。

- 采集 → 锁屏：`screenLockedNotification` 触发关闭；关闭区间 `protectedStateClosed` 到 `captureSessionStarting`，聚合 2→2、handoff 4→4、durable 3→3，锁屏期间 observe 均为 `locked`。
- 解锁后锁 provider 收到解锁通知（`notification=unlocked`）。第一次显式 Start：`prepareLockRead=unlocked`、`prepareOutcome=ready`、readiness 返回 unlocked，进入采集且会话存活。
- 菜单 Quit：执行 1 次 flush，结果 `saved`，阶段到 `stopped`，进程正常退出并写出摘要（`flushIssued`=`flushDurable`=12，无失败、超时或作废）。
- 锁屏界面期间 witness 多次读到安全输入 `enabled`。
- 聚合共 21 次，超过约定的 3 次：采集期间还有其他键盘输入（很可能是和执行者对话的打字）。计数本身不影响 Start/Quit 结论，但本轮不能作为输入隔离的计数证据。

本次没有复现上一轮“解锁后 Start 不恢复、Quit 不退出”。

### 2026-09-26 密码框测试（用户批准，结果无效，发现新缺陷）

证据 `.build/round3-evidence/`；第一次尝试因操作顺序有误作废，证据保留在 `.build/round3-attempt1-void/`。

- 启动约 4 秒后（执行者用 `open -a Safari` 打开本地测试页的时刻），会话失效：`captureSessionLive=false`，但阶段仍是 `collecting`。整次运行 tap 回调为 0，所以本轮不能回答“密码框期间按键是否被计数”。
- witness 在密码框期间读到安全输入 `enabled`，缓存状态仍为 `disabled`。Quit 执行了 1 次 flush，结果 `saved`，正常退出；真实 store 目录未改动。
- 离线复现（`testFailedAutomaticRecoveryLeavesAnActionableState`）：前台切换触发自动恢复，若恢复期间前台再次变化，重建失败（`startFailed`）。失败时事件源连同前台监听一起停止，之后再没有自动触发；阶段停在 `collecting`，Start 因 `not-blocked-or-failed` 直接返回，只能重启。实机日记没有记录协调器结果，所以实机上具体是哪一步失败没有直接证据，只有时序和状态吻合。
- 修复（用户选择）：自动恢复以 `startFailed` 结束、会话确实已失效时，先在门控仍打开的情况下 flush 已保留的计数，然后转入 `blocked(keyUnavailable)`，由显式 Start 走完整检查重建。flush 失败则保留未保存标记，Quit 按合同继续拒绝。修复前测试失败的日志是 `fg-recovery-red2.log`，修复后通过的日志是 `fg-recovery-green-1..3.log`。

### 2026-09-26 密码框重测（用户批准，带上述修复）

证据 `.build/round4-evidence/`；`source-changes.patch` 的 SHA-256 为 `dc233279…2cf5`。本轮先打开测试页，再启动产品。

- 密码框期间：witness 读到安全输入 `enabled`，产品缓存仍为 `disabled`，会话存活；聚合停在 2、handoff 停在 4，两次在密码框里的按键没有到达 tap。这是单机单次观察，不证明所有安全输入场景。
- 关闭页面时安全输入仍为 `enabled`，前台切换触发的自动恢复失败，产品进入 `blocked(keyUnavailable)`（上面修复的行为）。之后在 TextEdit 的按键没有计数，需要显式 Start。
- Quit 卡住，实机复现了上一轮现象。日记只有菜单那次 Quit（`quitDecision=terminate`），没有 `applicationShouldTerminate` 那次。`stuck-sample.txt` 显示主线程停在 `requestQuit` → `NSApp.terminate` → `_shouldTerminate` → 嵌套事件循环。根因：菜单 Quit 在主 actor 任务里调用 `terminate`；非 `stopped` 阶段委托返回 `.terminateLater`，它的回复任务也要在主 actor 上运行，而当前任务正卡在嵌套循环里，所以死锁。进程由 SIGTERM 结束，没有退出摘要；真实 store 未改动。
- 修复：菜单 Quit 已判定可以退出时，`terminate` 同步回调委托，委托直接复用这个判定并返回 `.terminateNow`；系统发起的终止仍走 `.terminateLater` 重新检查。修复前测试失败的日志是 `quit-nested-red.log`，修复后通过的日志是 `quit-nested-green-1..3.log`。修复后尚未在实机上验证。

### 2026-09-26 Quit 修复实机验证与安全输入自检（用户批准）

- 产品现在在采集阶段按 250 ms 间隔轮询安全输入状态（只读布尔值）。250 ms 是轮询间隔，不是严格的最大响应时间；一次读取、协调器恢复或主线程繁忙都会把实际响应拉长。变为 enabled 或 unknown 且会话存活时，立即撤销队列、隐藏统计，交给恢复协调器关闭会话；阶段保持 `collecting`。恢复为 disabled 时自动请求一次恢复，重新走完整检查。安全输入未结束时，重建失败不会转入需要手动 Start 的 `blocked`；是否结束以恢复失败时的新读数为准，不用缓存。锁屏仍然需要显式 Start。轮询的 CPU 开销没有测量。
- Quit 实机验证：证据 `.build/round5-evidence/`，`source-changes.patch` 的 SHA-256 为 `5944f310…0b79`。采集 → 锁屏（`screenLockedNotification`，进入 `blocked`）→ 解锁 → 不按 Start 直接菜单 Quit。结果 `quitDecision=terminate`，进程正常退出并写出摘要，日记写入无失败；真实 store 未改动。上一轮卡死的路径已经不再卡死。
- 安全输入自检实机验证：证据 `.build/round6-evidence/`，候选版本与 Quit 验证相同。
  - 安全输入变为 enabled 后，下一次采样即由 `secureInputMonitor` 关闭会话，阶段保持 `collecting`。
  - 密码框期间聚合停在 2。
  - 关闭页面、安全输入恢复为 disabled 后，自动恢复会话，之后在 TextEdit 的按键计入，聚合为 3。
  - 页面打开期间安全输入短暂变为 disabled 一次，产品随即重建会话，再次 enabled 时又关闭，这段时间没有计数；共建立 7 次会话。
  - Quit 执行 1 次 flush，结果 `saved`，正常退出（`flushIssued`=`flushDurable`=7）；真实 store 未改动。
  - 这是单机单次观察。轮询间隔是 250 ms，不保证严格最大响应时间；安全输入短暂关闭的窗口内，产品会合法地恢复采集。
- 清理（用户批准）：删除了钥匙串 `com.keyrecord.trial.round2` 下的 `metadata` 和 `master-v1` 两项，以及隔离 store `.build/round2-trial`。之后又删除了上一轮留下的 `com.keyrecord.trial.round1`（`metadata`、`master-v1`）和 `.build/round1-trial`。生产命名空间和真实 store 未改动，证据目录保留。上一轮的构建不同，而且当时没有动作记录，那次失败的原因仍未确定。

### 2026-09-26 PR #9 合并前：监视任务生命周期与存储维护

详细记录见 `docs/PR9_MONITOR_LIFECYCLE.md`。本轮只做离线复现和修复，没有新的实机测试。

- Bugbot 指出的陈旧 `secureInputMonitor` 句柄已用产品真实组装 + 合成宿主复现：`sessionChanged` 走 `closeProtectedState()`（只 `sync()`，不调和监视任务），任务自行退出后句柄仍非空，下一次采集不再监视。锁屏路径因为解锁会 `syncRuntime()`，原先就能清掉句柄。
- 修复：`closeProtectedState` 和 `hooks.stop` 取消并清空句柄；任务用 generation 识别过期读数；自行退出时只清自己的句柄；维护期间 `holdRuntimeTasks` 阻止 `menuWillOpen` 把监视拉起来。
- 存储维护：隐私关闭后、门控仍关着时，重置/删除被拒绝并提示 `flow.actionUnavailable`，数据和采集意图保留。Start/Resume 打开门控后，重置清零、删除清掉临时 store 和钥匙串替身。失败的重置不再停在无会话的 `collecting`。随后的独立评审在 `f6839feb` 上复现了两个 P1：Start 会丢掉未保存计数，以及 quiesce 之后 writer 没有恢复、采集无法落盘。这两项已另行修复，详见 `docs/PR9_MONITOR_LIFECYCLE.md`。没有操作真实统计库。
