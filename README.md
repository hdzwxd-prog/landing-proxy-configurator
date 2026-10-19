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
4. 推荐“仅 Claude/浏览器”：保持系统代理不变，使用桌面上的 Claude/Edge 落地启动器。Edge 使用独立用户目录，已有窗口不接管。其他应用（包括 Codex）继续使用原系统代理。
5. “刷新状态”和“检测出口”均进行真实出口检测并同步更新状态。成功结果只在同一链路内短期有效；失败、切换或过期不会继续显示旧的绿色成功结果。

“仅非中国”和“全局”模式会将系统代理指向 18484，因而可能影响跟随系统代理的 Codex。“仅 Claude/浏览器”不会这么做。点 × 是收进托盘；“彻底退出”才停落地服务。独立应用中已经建立的连接是否重试/回落取决于客户端；本程序不保证所有程序在异常退出后都能无缝迁移已有连接。

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

`python tests/test_landing.py --report <report.json>` 使用独立 18684 / 19690 / 18683 / 18682 端口，验证两个实际出口、SSH 经第一跳、切回清理、上游不可用时禁止直连、失败保留原选择和关闭模式保存行为。需要本机 Mihomo、Python + PyYAML、可用 Clash 接口和已有 NAS04 SSH 密钥。前后对比系统代理、生产监听 PID 和选择文件；不关闭上游客户端进行故障测试。凭据临时副本仅在 `.ssh` 下使用并清理。

此实现与 Clash Verge 链式代理使用相同的 Mihomo 能力，但实例和配置独立。原德国使用 `dialer-proxy`，NAS04 使用显式代理的 TCP 隧道。

参考：[Mihomo 流量隧道](https://wiki.metacubex.one/config/tunnels/)、[dialer-proxy](https://wiki.metacubex.one/en/config/proxies/dialer-proxy/)。

不要提交运行时 YAML、controller secret、VLESS UUID、WebSocket 路径、订阅链接、SSH 私钥或密码。
