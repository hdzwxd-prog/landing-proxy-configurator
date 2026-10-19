# 落地代理配置器

Windows 桌面托盘程序，用于把本机系统代理固定到独立的 Mihomo 入口 `127.0.0.1:18484`，再由该入口通过德国 VLESS/WSS 落地。第一跳现在通过一个可配置的 Clash 兼容本地接口连接，默认是 Clash Verge 的 `127.0.0.1:7980`。

## 使用方式

1. 在 Clash / Clash Verge 中添加任意订阅，并在 Clash 自己的代理组里选择订阅和节点。
2. 打开“落地代理配置器”，在“Clash 接口”填写 Clash 提供的本地 HTTP/SOCKS 混合接口，例如 `127.0.0.1:7980`。
3. 点击“应用接口”，选择“仅非中国走德国”或“全局走德国”，再用“出口检测”确认公网 IP。
4. 订阅 URL、订阅名称和节点名称都不写入本程序；程序只消费 Clash 的本地代理接口。
5. 选择“仅 Claude/浏览器”时，程序只启动 18484，不改 Windows 全局代理；使用桌面上的 `Claude-落地代理.ps1` 或 `Edge-落地代理.ps1` 启动对应应用。Edge 使用独立的 `LandingProxyEdgeProfile`，现有 Edge 窗口不会被接管。
6. 选择“关闭德国转发”或退出程序后，18484 停止；Clash Verge/WandaCloud 自己的进程和端口不由本程序停止。

程序保留 `Wanda-Upstream` 作为兼容接口，但不再把 BigAirport 或任何单一订阅当作产品逻辑。选择文件和配置位于 `%USERPROFILE%\.ssh\GermanyRouter`，源代码和脚本在本目录。

## 链式代理关系

本程序使用 Mihomo 的 `dialer-proxy`：德国 `Germany-VLESS` 连接通过 `FIRST-HOP` 组建立，`FIRST-HOP` 当前指向 Clash 的本地接口。它和 Clash Verge/Mihomo 的链式代理是同一种内核机制，但这里是两个独立的 Mihomo 实例：Clash Verge 负责订阅和节点选择，独立 18484 实例负责德国落地和 Windows 系统代理。它不是把 Clash Verge 的订阅复制进本程序，也不是自动选择节点。

参考：

- Mihomo `dialer-proxy` 文档：<https://wiki.metacubex.one/en/config/proxies/dialer-proxy/>
- Clash Verge Rev 配置文档：<https://github.com/clash-verge-rev/clash-verge-rev.github.io/blob/main/docs/guide/config.md>

## 构建

本机没有要求安装 .NET SDK；使用 Windows Framework C# 编译器即可：

```powershell
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /target:winexe /out:落地代理配置器.exe /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Net.Http.dll .\GermanyProxyManager.cs
```

不要把 `%USERPROFILE%\.ssh\GermanyRouter` 下的 controller secret、VLESS UUID、WebSocket 路径或运行时配置提交到公开仓库。
