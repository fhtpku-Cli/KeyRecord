# PR #9 合并前：Secure Input 监视任务与存储维护

日期：2026-09-26。分支 `codex/privacy-measure-tools`。工作树 `/Users/bytedance/Documents/KeyRecord-measure-prep`。针对已评审提交 `3599851b1e7af966c11100ec92b8c149ba41b01b` 上的 Bugbot 线程 `discussion_r4107773583`。

本文件只记录离线复现、修复和测试。没有新的实机采集、锁屏、密码框、系统权限或真实钥匙串操作。单机 Debug 通过不等于 Phase 1 正式验收。

## 根因

采集阶段的 `secureInputMonitor` 只在 `syncRuntime()` → `reconcileSecureInputMonitor()` 里创建或取消。任务在 `phase != collecting` 时自行 `return`，但不会清空 `secureInputMonitor`。

两条真实退出路径不调用 `syncRuntime()`：

1. `handlePrivacyInvalidation()`（不可自动恢复的失效，例如 `sessionChanged`）→ `closeProtectedState()`。后者取消 pulse 和暂停隐私任务，然后 `sync()`，不调和监视任务。
2. `hooks.stop`（重置/删除的 `beforeMaintenance`）取消 pulse，把 UI 设为 blocked，但不改 `lifecycle.phase`，也不取消监视任务。维护期间 `menuWillOpen` 仍会 `syncRuntime()`；若阶段还是 `collecting`，旧句柄会被当成活的，或者已取消后又被立刻重建。

`closeProtectedState` 之后如果没有任何一次“非 collecting 的 `syncRuntime()`”，下一次回到 collecting 时 `guard secureInputMonitor == nil` 会跳过启动。锁屏路径碰巧安全：解锁会 `handleRuntimeAvailable()` → `syncRuntime()`，此时阶段已是 blocked，句柄被清掉。

过期任务的第二层风险：旧任务若停在 `secureInputState()` 或协调器 `await` 上，新监视启动后，旧读数仍可能按过期的 enabled/disabled 关闭或重开采集。

## 修复

最小改动，不削弱既定恢复、锁屏显式 Start、暂停意图或权限检查。

- `stopSecureInputMonitor()`：取消、置空、重置 `lastSecureInput`、递增 generation。
- `closeProtectedState()` 和 `hooks.stop` 都调用它。`hooks.stop` 另外设置 `holdRuntimeTasks`，维护期间即使阶段仍是 collecting 也不再启动监视。
- 任务在每次 `await` 之后核验 generation、`holdRuntimeTasks` 和 `phase == .collecting`。自行退出时只在 generation 仍匹配时清空句柄，对齐 pulse 的 `releasePulseOwnership`。
- `hooks.start` 和显式 Start/Resume/Accept 清掉 hold。维护失败不再复用 `settleFailedRecovery` 的忽略错误 flush；见下一节。

250 ms 是轮询间隔，不是严格最大响应时间。读取、协调器恢复和主线程繁忙都会延长实际响应。

## 复现（修复前，提交 3599851b）

命令：

```
xcodebuild -project KeyRecord.xcodeproj -scheme KeyRecordApp -configuration Debug \
  -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath .build/pr9-monitor-repro \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:KeyRecordAppTests/ProductRecoveryQuitTests test
```

失败（6 个断言 / 3 个用例）：

- `testMonitorSurvivesPrivacyClosureThatSkipsTheUnlockSync`：`sessionChanged` → Start 后，开启 Secure Input 不再关闭会话。
- `testMonitorRestartsExactlyOncePerCollectingEntryAcrossRepeatedClosures`：第一轮同样丢失监视。
- `testMonitorDoesNotActWhileMaintenanceRuns`：删除过程中监视把生命周期从 `collecting` 推到 `blocked`，并额外做了 readiness。

当时通过、说明调用链不同：

- `testMonitorSurvivesLockUnlockAndStart`：解锁会 `syncRuntime()`。
- `testPauseAndQuitStopTheMonitorAndClearingSecureInputCannotReopen`：暂停和退出走 `syncRuntime()`。

原始 xcodebuild 输出在工作树 `.build/pr9-monitor-repro/`（不提交）。

## 存储维护观察

全部使用临时目录加密 store 和 `MemoryKeychain`，没有碰真实统计库或钥匙串。

| 路径 | 结果 |
| --- | --- |
| 暂停 → 锁屏 → 解锁 → 不 Resume 就重置 | 拒绝，`flow.actionUnavailable`，保持 paused，计数仍在；Resume 后计数仍为 2。门控在显式恢复前保持关闭，没有走到 `resetCycle` 的 `storeNotInitialized`。 |
| 同上但先 Resume 再重置 | 成功，采集继续，计数 0。 |
| 采集 → 锁屏 → 解锁 → Start → 重置 | 成功，采集继续，计数 0。 |
| 锁屏后 blocked 直接删除 | 拒绝，数据仍在；Start 后删除成功，临时 store 和钥匙串替身被清掉，回到 `unstarted`。 |
| 采集中重置遇到只读 store | 修复前停在无会话的 `collecting`，Start 因 `not-blocked-or-failed` 直接返回。修复后进入可 Start 的 blocked，恢复权限后 Start 能重建会话。采集意图 `expectedCollecting=true` 保留。 |

结论：隐私关闭后的重置/删除并不是 `save()` 那种“会话已关闭却继续写”的同构缺陷；它们先被锁门控挡住。Start/Resume 会重新 `bootstrap()`，之后维护正常。真正的缺陷是失败重置留下死的 collecting。

## 验证命令与结果

修复后同一组测试：`ProductRecoveryQuitTests` 30 项，0 失败（约 39 s）。覆盖：

1. 采集 → 锁屏 → 解锁并 Start → 再开 Secure Input，仍能关闭采集。
2. 连续两轮关闭与恢复，监视各启动一次，不重复。
3. 暂停、退出、维护正确管理监视；维护中变化安全输入不会重开采集。
4. 旧任务延迟返回 enabled/disabled，不会关掉新会话，也不会在暂停后重开。
5. enabled/unknown 保持关闭；disabled 后按原约定自动恢复，不绕过暂停、锁屏 Start 规则或权限。

完整验证（本工作树，修复后）：

| 命令 | 结果 |
| --- | --- |
| `swift test` | 517 项，0 失败（Store 162、Measurement 9、Integration 41、Core 228、Capture 65、Analysis 12） |
| `Scripts/test-capture-harness-offline.sh` | PASS，19 CLI + 6 离线检查，无真采集 |
| `swift build -c release` | 成功 |
| 通用 unsigned Release `xcodebuild`（arm64 + x86_64） | `BUILD SUCCEEDED` |
| Debug `build-for-testing` | `TEST BUILD SUCCEEDED` |
| `xcrun xctest` 无宿主 App 套件 | 相关恢复测试 30/30；全套在补上 Debug 预览窗 `animationBehavior = .none` 前有 1 项既有失败（`T22AppearanceTests` 发现 `AnalysisPreview.swift` 的 `NSWindow` 未关动画）。该项与监视任务无关，已按现有运动策略补上，不放宽检查。 |
| `Scripts/release-boundary.rb bundle` / `project` | PASS；二进制无 `LocalDevelopmentCapture` / `SystemSessionLockProvider` / `CaptureDiagnosticsRecorder` / `DebugTrialIsolation` |
| `Scripts/audit-product-network.sh` | PASS，静态检查，`liveReceipt=false` |

不把提交 `3599851b` 的 CI 绿标算作本提交的结果。

## 未验证范围

- 没有本轮实机：锁屏后再进密码框、真实 Input Monitoring、真实钥匙串。
- 没有测量 250 ms 轮询的 CPU 或足迹。
- 没有把本轮结果当作 Phase 1 正式验收。
- 自动审批曾声称 Bugbot 被跳过；以评审线程为准，不以自动批准为已解决问题。

## 独立评审复现的两个 P1（提交 f6839feb）

以 `REVIEW.md` 的最终裁定为准。原 30 项恢复测试通过，不能覆盖下面两条。没有把“pulse 重启必然中断删除”或“过期协调器事务”当成已确认缺陷。

### 已复现

1. **失败重置后 Start 丢掉未保存计数。** 合成产品保存 2 次，再计 1 次未保存，把临时 store 设为不可写后重置失败。恢复写权限并 Start。修复前内存和重新加载都是 2，再计 1 次后重新加载是 3，第三次计数丢失。原因：`afterFailure` 忽略 flush 错误并进入 blocked；Start 的 `scheduler.reopen()` 丢弃 pending，再从磁盘装回旧总数。
2. **失败重置后 Start 显示 collecting，但写不进去。** 2 次都已保存，没有 pending。不可写重置时，flush 成功，`quiesce` 暂停了 `SerialObjectWriter`，随后 `resetCycle` 失败。`writer.resume()` 只在成功路径。修复前显式 flush 抛出 `failed`，pending 仍在。
3. **已确认、但不是第三个 P1：** 删除挂起时打开菜单，`activePulseCount` 从 0 变成 1。`holdRuntimeTasks` 没有约束 `reconcilePulse`。没有证据表明这中断了删除或损坏数据。

失败前日志在工作树 `.build/pr9-p1-red/xcodebuild.log`（不提交）。

### 修复

按失败阶段处理，不在 `catch` 里无条件 `resume`：

- flush 失败、尚未 quiesce：writer 仍在接受写入，pending 保留。Start 在 `scheduler.reopen()` 之前先把 pending 写成功；写失败就停在 blocked，并保持门控打开，避免下次无法再写。锁屏仍走 `closeProtectedState`，继续丢弃未保存增量。
- drain 未完成：不 resume。Start 再试一次；writer 仍忙就继续 blocked，提示 `flow.actionUnavailable`。
- drain 已完成且没有重置日志：Start 时才 `resume` 空闲 writer，然后才能采集。
- 磁盘上已有未完成重置日志，或无法确认：不进入采集，留在可重试的 blocked。不把部分删除当成一次正常重置重放。
- 已关闭受保护会话或删除已经开始：不进入采集。
- `reconcilePulse` 在 `holdRuntimeTasks` 期间不再启动。菜单打开用主 actor yield 断言，不用长时间 sleep 推断安全。

### 修复后

`ProductRecoveryQuitTests` 33 项，0 失败。新增：

- `testFailedResetKeepsUnsavedCountsAndReloadsTheSameTotal`：恢复后内存为 3；重新加载仍为 3；再计 1 次并保存后重新加载为 4。无丢失、无重复。
- `testFailedResetAfterWriterSuspendCanSaveNewCounts`：恢复后新的 1 次能 flush，重新加载为 3。
- `testMenuOpenDoesNotRestartPulseWhileEraseIsHeld`：挂起的删除期间菜单打开后 pulse 仍为 0；放开后删除完成并回到 `unstarted`。

同一工作树还跑了 `swift test` 517 项 0 失败，`swift build -c release` 成功，通用 unsigned Release（arm64 + x86_64）成功。Release 边界和网络静态审计通过，二进制里没有 DEBUG 诊断名。这只是静态检查。

尚未验证：真实统计库、真实钥匙串、实机锁屏或密码框。本轮修复不是 Phase 1 正式验收。旧提交的 CI 绿标和 Bugbot 因额度跳过都不算这次复审通过。
