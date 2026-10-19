# Phase 2 A/B 隔离试用准备 — 2026-10-13

> 历史记录说明（2026-10-20 核对）：本页保留所述日期/提交的实现、命令和验证范围，其中“当前”“待实现”“下一步”仅指当时。本页不代表当前开发状态，最新状态见 [PROJECT_STATUS](../PROJECT_STATUS.md)，后续安排见 [ROADMAP](../ROADMAP.md)；本页不授权新实机、设备或删除操作。

- 当前决定：此准备轮次后置。B 已补齐后端检查，本文的较早签名包不覆盖该新增功能；后端稳定后再准备最终候选并集中补缺，不因 profile 到期要求现在试用。见 [B 完成记录](B_COMPLETION_20261013.md)。

状态：工程准备完成，实际试用未执行。用户同意合并 PR #21、核对签名并准备隔离包；真实 VIA/设备验证继续延期。本页是准备记录和后续操作说明，不能替代实际轮次的授权或观察结果。

## 本轮准备结果

[PR #21](https://github.com/fhtpku-Cli/KeyRecord/pull/21) 已于 2026-10-13 合并，主干提交为 `2c29f18e62648e2166fa089c4734d0cd2e92e908`。PR 最终提交的 push 与 pull_request CI 均通过，[合并提交的主干 CI 也已通过](https://github.com/fhtpku-Cli/KeyRecord/actions/runs/38300741351)，合并提交的文件内容与该最终提交一致；本轮没有重新执行已有本机离线套件。主目录历史改动保持原状，准备工作在隔离 `network-acceptance-closeout/KeyRecord` 完成。

已从该合并提交成功构建开发签名 arm64 Debug App，并通过既有 `launch-isolated-debug-trial.sh --check` 的签名、profile、应用 ID 和必需隔离配置检查。**没有安装、启动 App、读取应用钥匙串、采集输入或查询键盘设备。** 签名和构建不是有效钥匙串访问、产品 Collecting 或真实收益的证据。

| 项目 | 已观察状态 |
|---|---|
| 本机环境 | macOS 27.0.1，build 26A434；Xcode 27.0，27A266a |
| 源码 | 合并提交 `2c29f18e62648e2166fa089c4734d0cd2e92e908`，构建时工作目录干净 |
| App 身份 | `com.keyrecord.trial.mvp20260929`，团队 `P3W62C39TN`；沿用当前 profile 已授权的试用身份 |
| 证书 | 本机有效 Apple Development 身份与 profile 内证书一致，团队匹配，证书有效至 2027-09-13 |
| 实际内嵌 profile | `86a56be3-ecab-41ca-975f-b52de7e67f8d`，授权同一个 App ID；到期为 **2026-10-19 16:47:11 Asia/Shanghai**（08:47:11 UTC） |
| 签名权限 | `com.apple.application-identifier` 和 Keychain group 均为 `P3W62C39TN.com.keyrecord.trial.mvp20260929` |
| 隔离配置 | `KeyRecordRequiresTrialIsolation=true`；新的空 `live` 根目录权限 700，钥匙串命名空间为 `com.keyrecord.trial.mvp20260929.phase2ab20261013` |
| 本轮 App 启动 | 无。本轮只构建并做 `--check` |

实际包位于本机：

`/Users/bytedance/.codex/worktrees/network-acceptance-closeout/KeyRecord/.build/phase2-ab-trial-20261013-local/build/Build/Products/Debug/KeyRecordApp.app`

输出根目录为同一工作树下 `.build/phase2-ab-trial-20261013-local`，包含 `build.log`、空的 `live/` 和两份 `samples/synthetic-reference-*.json`。这些本地产物不提交到 Git，也没有上传签名包或 profile。清理工作树/`.build` 会移除包，届时需要重新准备。

两份实际交付 JSON 已通过临时 SwiftPM 命令调用现有公共 `VIAReferenceParser` 和 `PhysicalAnalysis`：配对输出为 1 层、4 个几何键位、3 个标准配置、0 个不支持配置；限制为 `deploymentUnknown` 与 `transformsUnknown`，设备为 unknown。`⌘A → F1` 仍返回逻辑键数 2→1，原因为 deviceUncertain。该实执行只读取两份自己创建的样例，没有启动 App；入口及日志位于 `/private/tmp/keyrecord-phase2-samples-check-20261013/`，不能替代系统文件选择器或真实 VIA 兼容观察。

构建命令：

```sh
bash Scripts/build-isolated-debug-trial.sh com.keyrecord.trial.mvp20260929 P3W62C39TN /Users/bytedance/.codex/worktrees/network-acceptance-closeout/KeyRecord/.build/phase2-ab-trial-20261013-local
```

使用已有本地自动选择路径，没有 `-allowProvisioningUpdates`。首次尝试显式传 profile UUID，因全局 `PROVISIONING_PROFILE_SPECIFIER` 被套到 SwiftPM 库目标而在签名设置阶段失败；改用脚本原有本地自动选择方式后成功。失败输出保留在 `.build/phase2-ab-trial-20261013/build.log` 与 `/private/tmp/keyrecord-phase2-ab-trial-build.log`，成功输出在上述最终目录的 `build.log` 与 `/private/tmp/keyrecord-phase2-ab-trial-local-build.log`。本轮没有修改脚本的可选手工 profile 分支，该分支在本机工具链下的限制保留为已知问题。

## 之后集中试用的短流程

当前不需要用户操作。之后准备试用时，先确认包仍在、profile 仍有效、旧的同身份 MVP Trial 已退出；再由用户明确发起这一次实际轮次。没有签名材料更新、安装替换或权限切换的默认授权。

1. 从下面的隔离启动命令启动本轮暂存包，按实际同意流程进入 Collecting。若遇到钥匙串/权限异常，记录实际提示并停止；不借用日常 App 的数据或设置来绕过。
2. 在空白 TextEdit 文档中按两次 `⌘A`，随后通过菜单暂停，查看快捷键统计和应用归属。样本仅两次、单个自然日，**不要求出现 Top 5 或合格推荐**；已有合成跨日资格测试保持独立范围。
3. 设置中选择 F1，分别选取 `samples/` 的配置副本与定义，检查匹配摘要和未知证据提示。候选详情中的位置数量只是第 0 层参考，比较和排名仍为逻辑口径，后端仍未连接。
4. 正常退出，再用同一命令重开。核对统计与 F1 选择保留，VIA 会话参考已移除。结束后正常退出，统一记录实际结果及任何失败。

以上两份 JSON 是明确合成的 2×2 静态样例，仅用于实际文件选择器/只读展示流程，不是真实键盘配置。真实 VIA 副本、对应定义、当前部署与设备证据仍留后；不因此升级物理口径。这个短流程也不是锁屏、权限切换、网络观察、性能或完整 G2 验收。

**后续实际轮次确认后才执行**的启动命令：

```sh
bash /Users/bytedance/.codex/worktrees/network-acceptance-closeout/KeyRecord/Scripts/launch-isolated-debug-trial.sh /Users/bytedance/.codex/worktrees/network-acceptance-closeout/KeyRecord/.build/phase2-ab-trial-20261013-local/build/Build/Products/Debug/KeyRecordApp.app /Users/bytedance/.codex/worktrees/network-acceptance-closeout/KeyRecord/.build/phase2-ab-trial-20261013-local/live com.keyrecord.trial.mvp20260929.phase2ab20261013
```

该入口显式传入试用 store/namespace，并清除 `CFFIXED_USER_HOME`；本次 App 缺失这些隔离参数时必须拒绝进入生产数据路径。直接双击暂存或旧安装 App 不是本页约定的启动方式。`live/store` 和应用钥匙串条目将在未来实际同意/保存时才创建；本次仅准备了空目录。

## 尚未验证

系统文件选择器的实际授权、真实加密偏好重开、真实输入统计与产品归属、当前设备/部署/变换链都未在这个新包上观察。profile 有效期短：若试用在到期之后，先重新核对和准备当前有效材料，不能复用本次签名状态作为持续有效证明。工程基础合并和可启动输入检查不等于完整增量 B、FR-R/FR-E、G2 或发行完成。
