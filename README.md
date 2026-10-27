# 落地代理配置器

独立的 Windows 托盘程序。Clash / Clash Verge / WandaCloud 管理订阅和节点，本程序读取其本地代理接口，再连接用户选择的落地出口。程序不启动、停止或配置 Clash/Wanda，不修改其订阅、节点、端口或 TUN。

## 两个独立选择

- **第一跳来源**：本地 Clash 混合 / HTTP 接口（现场端口为 7980；其他端口按客户端实际配置填写），或 WandaCloud SOCKS 7892。软件不再保存或选择任何订阅 / 节点。旧 BigAirport 入口迁移到已有的 Clash 本地接口。
- **落地出口**：原德国 VLESS/WSS `192.248.188.234:443`，或 NAS04 `212.121.132.230`（SSH 用户 `h50055690`）。NAS04 是替代的最终出口，不是叠加在德国前面的第一跳。

链路：

```text
应用 -> 独立入口 18484 -> 所选 Clash/Wanda 接口 -> 所选落地 -> 网站
                                               ├ 原德国：VLESS/WSS 443
                                               └ NAS04：SSH 22
```

NAS04 使用 Windows OpenSSH 动态 SOCKS：本地 `18583` 提供 SOCKS，`18584` 将 SSH 字节流通过 `FIRST-HOP` 转发至 NAS04 的 22 端口。SSH 只连接 loopback 转发端口，以 NAS04 原地址验证已知主机密钥；上游不可用时不会直连 NAS04。无需在 NAS04 安装新服务。SSH 密钥及 known_hosts 仍由 OpenSSH 管理，程序不存密码。

## 使用

1. 自行启动 Clash/Wanda，并在客户端内选择订阅和节点。
2. 打开桌面“落地代理配置器”，按实际端口填写接口并点击“应用接口”；使用 Wanda 时选第一跳来源并点击“应用第一跳”。
3. 在“落地出口”中选择原德国或 NAS04，点击“应用落地”。运行时会检测实际公网 IP；失败则保留原选择。关闭模式只保存选择，启用后才连接。
4. 推荐“仅指定应用”：保持系统代理不变。Claude 使用原生应用代理配置。勾选 **“Edge 使用落地代理（含默认链接）”**，日常 Edge 的普通窗口、默认浏览器链接及邮件登录跳转统一使用落地；保留原来的账号、书签和历史，不另建专用浏览器。首次应用时按 Windows 提示授权，保存网页工作后完整退出并重开 Edge，再点击“检查 Edge 出口”。
5. “刷新状态”和“检测出口”均进行真实出口检测并同步更新状态。成功结果只在同一链路内短期有效；失败、切换或过期不会继续显示旧的绿色成功结果。

“仅非中国”和“全局”模式会将系统代理指向 18484，因而可能影响跟随系统代理的 Codex。“仅指定应用”不会这么做。点 × 是收进托盘；“彻底退出”才停落地服务。固定落地的 Claude/Edge 在落地停止时连接失败；要让 Edge 恢复原路线，取消 Edge 开关。切换代理不保证已有连接无缝迁移。

“仅指定应用”下，接入 18484 的公共网站流量统一走所选落地，不继承“仅非中国”模式的国内直连规则。本机、局域网及 `slai.edu.cn` 校内服务保留直连例外。

## Claude 桌面客户端与浏览器

运行 `Install-App-Launchers.ps1` 部署应用启动器，运行 `Configure-Claude-Landing.ps1 -Action Enable` 为 Claude 配置其原生 `egressProxyUrl=http://127.0.0.1:18484`。使用 Claude 支持的用户级 `%LOCALAPPDATA%/Claude-3p/configLibrary` 配置；现场 MSIX 版本也从此处读取，与账号数据使用的虚拟化 Roaming 目录不同。保留已有配置项及备份，不修改账号、认证或部署模式。机器/用户管理策略优先时拒绝假装覆盖。需要 Claude 1.44121.1 或更新版本。

- 配置只在 Claude **完整退出后重开**时生效。已有 Code/Cowork 任务不会被启动器强制结束。
- 生效后普通 Claude 图标也会加载专用代理；落地停止时该客户端的代理请求失败，不自动回落。Clash/Wanda 和 Codex 不依赖本设置。
- “核对 Claude 连接”检查一次当前 TCP 连接。发现 7980/7892/7890 或外部直连时报告异常；无连接时报未验证。有 18484 连接也只说明本次观测，不保证每个功能或后续请求。
- Claude 更新器、外部浏览器登录、SSH 远端会话、忽略代理变量的工具有独立网络路径。代理配置不能替代系统防火墙；不宣称绝对防泄漏。
- `Configure-Claude-Landing.ps1 -Action Restore` 只恢复本次修改的代理字段，完全退出并重开 Claude 后恢复原路线；不会自动执行。
- `Start-Claude-Code-Landing.ps1` 才是命令行启动器，环境变量仅作用于该进程链，执行后恢复调用环境。
- Edge 使用当前 Windows 用户的 `Software\Policies\Microsoft\Edge` 策略，`ProxySettings` 固定为 `127.0.0.1:18484`，同时限制 WebRTC 非代理 UDP、关闭 QUIC、默认拒绝定位。代理策略支持动态刷新，QUIC / WebRTC 策略要求重开浏览器。微软说明 WebRTC 策略不适用于登录个人 Microsoft 账号的配置；不能将策略写入等同于所有账号场景都已验证，也不能据此承诺绝对匿名。
- `Configure-Edge-Landing.ps1 -Action Enable -AllowElevation` 启用，`-Action Restore -AllowElevation` 恢复原值或原来的缺省状态。首次备份在 `.ssh\GermanyRouter\edge-policy-state.json`；仅恢复本程序拥有的四项策略，发现其他程序的后续修改时拒绝覆盖。若检测到计算机级管理策略则拒绝假装覆盖。此机策略目录只允许管理员写入，因此切换时会请求 Windows 授权。
- 安装器移除旧的专用 Edge 桌面入口并保存到运行目录的 `retired-edge-launchers`；不再启动 `LandingProxyEdgeProfile`，也不删除其中可能已有的用户数据。“检查 Edge 出口”只打开日常 Edge。

未启用 Edge 用户策略时，`node tests/test_browser_landing.mjs <report.json>` 在独立、未登录的临时 Edge 配置中验证落地 IP、WebRTC 和代理断开。WebRTC 使用本地 STUN 服务返回文档保留地址作为测试标记，不将用户真实 IP 发往外部 STUN 测试站。对照组应出现标记，保护组应无 UDP 包/候选地址；不可达代理应返回 `ERR_PROXY_CONNECTION_FAILED`。它不验证 Claude 桌面客户端的 WebRTC。

启用当前用户的 Edge 策略后，改用 `node tests/test_browser_landing.mjs <report.json> --policy`：不设置命令行代理或 WebRTC 偏好，检查新启动的 Edge 仅依赖 Windows 策略时的实际出口和本地 STUN 行为。此时不运行不可达代理对照，因为 Edge 策略会覆盖测试命令行的代理端口；不为测试而切断生产落地。临时配置仅用于自动测试，不是交付给用户的专用浏览器。

`powershell -File tests/test_edge_policy.ps1` 在独立临时注册表项中验证启用、重复启用、恢复原值/类型、保留无关设置和外部修改冲突保护，不修改真实 Edge 策略。

参考：[Claude 原生代理及绕行边界](https://claude.com/docs/third-party/claude-desktop/network-proxy)、[配置来源与优先级](https://claude.com/docs/third-party/claude-desktop/mdm)、[Edge 代理策略](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/ProxySettings)、[WebRTC 策略适用范围](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/WebRtcLocalhostIpHandling)。

## 源码、配置和升级

本仓库是源码；本机运行配置位于 `%USERPROFILE%\.ssh\GermanyRouter`，SSH 启停和路由监督脚本位于 `%USERPROFILE%\.ssh`。`landing-choice.txt` 保存落地选择，`upstream-choice.txt` 保存上游选择。敏感运行配置不进入 Git。

- `GermanyProxyManager.cs`：界面、状态检测。
- `Landing.Common.ps1`、`Set-Landing-Exit.ps1`：出口验证、运行时选择和失败回滚。
- `Ensure-Clash-Upstream.ps1`：更新自有配置，保留本机现有节点凭据。
- `Start-NAS04-Socks.ps1`、`Stop-NAS04-Socks.ps1`：隧道及精确 PID/创建时间清理。
- `Start-Germany-Router.ps1`：自有 Mihomo 监督，不控制上游客户端。独立核心使用 `landing-router-core.exe`，避免上游按 Clash 核心进程名识别时发生回环排除。首次启动从本机 Mihomo 复制内核，不修改 Clash 原文件。

构建（无需 .NET SDK）：运行 `powershell -File .\Build.ps1`，产物在 `bin/LandingProxyConfigurator.exe`；也可使用下面的命令。

```powershell
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /win32manifest:app.manifest /out:落地代理配置器.exe /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Net.Http.dll .\GermanyProxyManager.cs
```

部署时，将 `Landing.Common.ps1`、`Set-Landing-Exit.ps1`、`Set-Germany-Upstream.ps1`、`Ensure-Clash-Upstream.ps1` 放入 `GermanyRouter`；其余运行脚本放入 `.ssh`。先备份待替换文件，再编译并更新桌面 EXE。代码中的部署路径对应本机用户。更新监督脚本时需要加载新监督进程；保留已有 Mihomo 及系统代理，避免中断其他应用。

## 验证

### 2026-10-27 稳定性修复

- 总监督遇到 NAS04 启动失败时保持运行；每 30 秒验证真实出口。连续两次失败时仅重建同一 NAS04 隧道，两次恢复操作至少间隔 120 秒，不自动换上游或落地。
- 控制口请求暂时失败不会结束监督。监督异常退出时保留现有转发，写入降级状态，不顺带停止 SSH 或修改系统代理。
- UI 检查独立监督心跳，超过 90 秒明确报告失联；“仅指定应用”但系统代理仍为 18484 时明确显示冲突。
- 外部维修删除 Edge ProxySettings 后，可以显式使用 `Configure-Edge-Landing.ps1 -Action Enable -RepairMissingProxy -AllowElevation` 恢复缺失项。保留首次恢复备份，其他策略被修改时仍拒绝覆盖。修复允许在落地异常时写入固定代理，以保持失败断网。
- 某次 SSH 无法经过一个上游，不足以证明整个订阅永久封禁 22。应区分 CONNECT 响应、SSH 握手、隧道建立和最终出口；单次“出口健康”不是长期稳定性保证。

`python tests/test_landing.py --report <report.json>` 使用独立 18684 / 19690 / 18683 / 18682 端口，验证两个实际出口、SSH 经第一跳、切回清理、上游不可用时禁止直连、失败保留原选择和关闭模式保存行为。需要本机 Mihomo、Python + PyYAML、可用 Clash 接口和已有 NAS04 SSH 密钥。前后对比系统代理、生产监听 PID 和选择文件；不关闭上游客户端进行故障测试。凭据临时副本仅在 `.ssh` 下使用并清理。

此实现与 Clash Verge 链式代理使用相同的 Mihomo 能力，但实例和配置独立。原德国使用 `dialer-proxy`，NAS04 使用显式代理的 TCP 隧道。

参考：[Mihomo 流量隧道](https://wiki.metacubex.one/config/tunnels/)、[dialer-proxy](https://wiki.metacubex.one/en/config/proxies/dialer-proxy/)。

不要提交运行时 YAML、controller secret、VLESS UUID、WebSocket 路径、订阅链接、SSH 私钥或密码。
