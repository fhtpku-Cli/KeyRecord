# PR #10 合并版：单页安全输入回归

被测源码：`64590a0e9b57a55af9a23921983f2c16bb59c62e`（PR #10 合并提交）。
独立 Apple Development 签名 Debug、arm64；本机 Safari，由用户批准并亲自操作。
构建位于 `.build/pr10-signed-regression/Build/Products/Debug/KeyRecordApp.app`。
本轮测试进程 PID 48735。没有替换日常 App，没有正式 Release 或性能测量。

## 观察结果

| 环节 | 证据 | 结论范围 |
| --- | --- | --- |
| 普通输入 | 本进程 aggregateDelta 从 0 到 3，关闭前 durable 写入累计为 5 | 三次输入计入，存在自动写入成功记录 |
| 安全输入开启 | begin seq 34 → end seq 109；区间内 37 条 enabled witness（全轮 38 条，含 begin 前 seq 32） | 观察到采集停止、展示状态隐藏 |
| 关闭区间 | handoffAccepted 12→12；normalizationOutput 6→6；aggregateDelta 3→3；受保护展示读取尝试与发布计数不变 | 记录覆盖的关闭区间没有新增计数；不宣称连续每个时刻或所有存储读取都被验证 |
| 自动恢复 | 独立读数 disabled 后 session live、展示状态可见；没有 Start/Resume 动作 | 观察到自动恢复；随后两次输入使本进程增量 3→5 |
| 保存与退出 | issued/returned/succeeded/durable 均为 8；失败/超时/失效均为 0；Quit seq 136/138 配对，saved、terminate、无未保存数据 | 菜单退出成功，摘要存在且精确 PID 已消失；未强杀 |

Safari 可访问性树确认页面从“尚未创建密码框”走到“操作步骤完成”，结束时没有密码框。
KeyRecord 的隐藏/恢复结论来自诊断展示状态，不是本轮逐帧屏幕检查。
沿用了前轮的隔离测试库，因此绝对统计值不为零；本表使用本进程增量。
本轮没有重启后重新解密核验，不能把写入成功记录扩写为本轮重启持久化通过。

最终摘要的通用 `captureSessionLive` 仍是 true；Quit 的实际读取
`actionDetail.sessionLiveAfter=false`。这是已有的摘要时点限制，退出依据是
配对 Quit 动作、退出摘要和进程消失，不能用该缓存字段推断进程仍在采集。
计数不是原子快照，见证为离散采样；不证明严格响应时间上限。
本轮 begin 的 boundaryCause 是 `closedStateObserved`，结论来自原始边界、见证和计数的人工核对，
没有把默认跳过该类边界的区间评估器说成自动判定通过。

## 证据与失败尝试

可随仓库保留的[数值证据摘录](../evidence/host-regression/pr10-singlepage/observations.json)
含原始选定行和完整退出摘要，没有按键内容、账号、密钥或本机用户名。
完整原始日记、本轮配置、构建和签名日志仍保存在本地
`.omo/evidence/pr10-secure-regression-k5hbym_6/`，不是新克隆必备文件。
试验数据库和钥匙串条目保留，未在本轮收尾删除；不上传它们。

前两次尝试保留但不算完整通过：

1. 临时 HOME/CFFIXED_USER_HOME 环境无法定位默认文件钥匙串；用户点击取消并正常退出，未进入采集。只读对照：正常环境 `security default-keychain -d user` 成功，覆盖环境失败。没有重置默认钥匙串。
2. 聊天往返导致密码框失焦和额外输入，随后正常退出。改成单页流程后才完成上表这一轮，不能把前轮计数混入本轮。

本轮采用显式 `KEYRECORD_TRIAL_STORE` 和专用 `KEYRECORD_TRIAL_NAMESPACE`，
不覆盖 HOME/CFFIXED_USER_HOME。该命名空间隔离条目身份，并非独立钥匙串文件。
未选择生产统计目录，也未主动读写已有生产钥匙串条目；这不是系统范围“零访问”的审计证明。

## 下一步

[单页操作流程](PRIVACY_RESOURCE_USER_STEPS.md#单页安全输入回归采集中)可重复使用。
本轮仅支持该版本、该主机的 Debug 安全输入停采/恢复/正常退出观察。
先按 [项目状态的收尾顺序](PROJECT_STATUS.md#worktree-closeout-and-evidence-order--2026-09-27)
整理现有改动与证据，并核查权限撤销/恢复的已有覆盖；不安排本页自动重跑。
Phase 1/G1 尚未验收：正式打字/空闲测量各三轮、Intel 实机、权限变化、快速用户切换、
实际网络观测及签名 Release 资格仍待完成。旧候选的锁屏和资源结果不能转记成本提交的新测量。
