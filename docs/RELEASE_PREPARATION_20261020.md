# 更新检查、许可与发布准备

正式名称 KeyRecord，自有代码 Apache-2.0，均为用户明确决定。第三方源码、历史证据及工具保留原许可；参见[第三方声明](../THIRD_PARTY_NOTICES.md)。

## 更新行为

应用启动后检查是否距上次尝试满七天，随后每小时检查到期条件。用户可主动重试。没有新增 Codex 定时任务、系统守护进程或登录辅助进程。失败也记录尝试时间，避免故障时持续联网；时钟回拨允许一次重新检查。全量删除成功后清除检查时间并停止本次会话检查。

唯一自动请求是固定的 HTTPS GET：`https://api.github.com/repos/fhtpku-Cli/KeyRecord/releases/latest`。请求不带行为统计、偏好、配置、机器标识、Cookie 或认证；临时 URLSession 不使用持久缓存和凭据。拒绝重定向、非 JSON、非 200/404 响应及超过 256 KiB 的数据。404 表示没有发布，网络/解析失败不会显示“已是最新”。取消和关闭使迟到结果失效。

仅比较两段或三段数字的稳定版本，拒绝预发布、草稿和不合法标签。版本页面从固定官方地址及合法标签构造，不采用服务器返回的任意 URL。用户在原生确认窗口确认后才打开浏览器，由用户手动下载、安装；无下载器、自动替换或重启。

`PrivacyEgressTests` 保留其他产品文件零网络/零子进程检查，只识别该客户端的已审查 API 和两个固定地址。`audit-product-network.sh` 默认严格模式保留；新产品使用 `--reviewed-updates`，仍拒绝其他网络栈、地址及 shell。测试同时实际运行模拟 HTTP 和原生按钮，不以扫描代替执行。静态通过不声称证明真实 TLS 流量、Apple 资格或所有依赖行为。

## 发布工具

`ruby Scripts/release-package.rb --output NEW_DIR --team TEAM --identity 'Developer ID Application: NAME (TEAM)' --notary-profile PROFILE` 默认只显示计划。

取得真实发布授权和凭据后，加 `--execute` 才会构建 Universal Release archive、检查现有发布边界和 Developer ID/Team、提交 Apple 公证、staple/validate、执行 Gatekeeper 检查，并在最后生成已装订应用的 ZIP。输出目录必须不存在；失败保留诊断目录，不覆盖或自动删除恢复资料。不会上传 GitHub Release 或公开发布。

离线测试 `ruby Scripts/test-release-package.rb` 使用模拟命令，覆盖成功顺序、旧目录拒绝、错误签名身份、公证拒绝及命令失败。模拟 ZIP 不属于实际发布包。真实签名、公证、下载、安装和启动验证继续后置。

## 许可

应用设置可读取随包附带的 LICENSE、NOTICE、Argon2-LICENSE.txt。Argon2 使用上游明确提供的 Apache-2.0 选项，源代码不修改；系统框架和 liblzma 不被重新分发。VIA/Vial/QMK/Karabiner 仍是独立应用或固件，不链接或随产品打包。

参考：[GitHub Latest Release API](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)、[Apache-2.0 原文](https://www.apache.org/licenses/LICENSE-2.0)。真实资格记录必须标明具体构建、系统、设备及动作，不能用离线结果替代。
