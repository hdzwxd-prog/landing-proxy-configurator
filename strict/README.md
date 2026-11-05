# 独立德国严格入口（分阶段部署，Code 完整验收未完成）

这组工具用于 Firefox 和 Claude 的固定德国出口，与可切换的通用 18484 入口分开。
18485 仅有 MATCH,Germany-VLESS，没有 DIRECT、NAS04、可变出口组或控制接口。
第一跳是明确选择的本机 HTTP/mixed 端口，没有自动选路。

`StrictNetworkLock.cpp` 使用 Windows 原生 WFP 持久过滤器，按应用路径和 Claude 包身份限定连接。
规则限制应用连接 TCP 127.0.0.1:18485，核心只能访问本机 TCP 第一跳。
核心的本地端口不固定，便于在 EXE 中手动选择 Clash/Wanda 和本机接口，不自动换路。
过滤器写入使用事务，只替换本工具自己的 provider；删除需要显式执行管理命令。
Firefox、Claude 客户端及其安装目录内程序的 91 条持久过滤器已安装，部分实际验证见下。
Claude Code 下载目录中的两个版本尚未加入现场规则，补装提权被取消。
需验证 Code 与桌面客户端的本机 IPC 兼容性，再部署其完整隔离。
Code/Cowork 任意子进程、虚拟机和共享 Python/Node 不因桌面程序规则自动获得保护。
未完成相应范围确认与验证前，不把它们计入受保护应用。

## 文件

- `generate_config.py` 从受保护的既有德国配置派生私有运行配置，不输出凭据。
- `firefox-policies.json` 全安装锁定代理并关闭直接回退、WebRTC、HTTP/3、定位及 DNS 预取。
- `Build.ps1` 编译 WFP 管理程序，需要 Visual C++ Build Tools 和 Windows SDK。
- `Install-Isolation.ps1` 经管理员授权安装隔离，`-IncludeClaude` 才同时安装 Claude 管理代理和包/程序规则。
- `Start-StrictGermany.ps1` 启动独立核心并检查德国实际出口。
- `Start-StrictApp.ps1` 在安装状态、代理策略和出口检查通过后启动应用；Claude 升级后要求重新检查。

凭据与运行产物在用户 `.ssh/GermanyRouter/StrictGermany` 内，目录 ACL 只允许当前用户、SYSTEM 和管理员。
没有修改系统代理、Clash/Wanda 节点、Codex 或现有 18484 服务。没有启用新的周期任务。
新版 EXE 源码提供独立的“Firefox / Claude · 德国强制通道”面板，Clash/Wanda 手选，停止与重连独立控制。
新面板对应的 EXE 仅构建，按用户要求暂未替换桌面版本。

## 2026-11-04 当前验证

- Mozilla 官方 Firefox 159.0.1 安装包 Authenticode 签名 Valid，签名者 Mozilla Corporation。
- 安装位置为 `%LOCALAPPDATA%/Programs/Mozilla Firefox`。
- 通过实际 Firefox Marionette 读取生效策略和锁定首选项，代理为 18485，WebRTC/HTTP3/直连回退关闭。
- 停止 18485 后，实际 Firefox 新导航收到 `proxyConnectFailure`，未回退访问测试网页。
- 策略阶段曾观测到 Firefox socket 进程的一条公网 TCP 443 连接，因此增加 WFP 限制，不能只凭策略写入判断保护生效。
- 新入口当前手动配置为 Wanda 7892，实际 Firefox 导航 api.ipify.org 返回 192.248.188.234。Clash 通道先前失败，不自动回退。
- 管理员已安装 91 条持久 WFP 过滤器与 HKLM Claude egressProxyUrl=18485；重开 Claude 后观察到 3 至 5 条 18485 连接，未观察到其他出口连接。
- 同规则测试程序能连接 18485，连接 7892、7980、18484、公网 IPv4 TCP、IPv6 loopback 返回 WSAEACCES 10013。
- 公网 IPv6 返回网络不可达 10051，不能将其算作 WFP 阻断验证。
- UDP sendto 返回成功；这不证明数据包已送达，需做接收侧验证，目前 UDP 验收未通过。
- Claude Code 的用户 settings.json 已配置代理环境变量，保留其他设置。其两个已安装原生引擎的系统过滤器补装提权被取消，尚未覆盖，也未验证完整 Code 会话。
- 用户现需使用 Claude，已冻结运行中的通道、客户端和网络规则。此后只离线修改、构建与备份；新 EXE、后续规则和断网/切换测试等待用户方便时再部署。
- 当前 Claude 客户端正常连到德国不等于任意 Code shell/Python/Node 子进程均被系统隔离。没有新增虚拟机，也没有全局封锁共享解释器。

只有上述剩余项实测通过后才能把“实施中”改为交付状态。固定出口不证明账号封禁原因，也不保证不会触发服务方账号限制。
## 2026-11-05 新版现场验收

- 桌面两个 EXE 已替换为 SHA256 44B9139FBFEDE0985010B82F32AA800DD3A5698DCD9B32281F8EA4946F89F163，新版界面已启动。
- 现场 18484 仍运行，18485 启动前缺失；没有日志证据证明退出根因。
- 界面点击停止成功，18485 连接拒绝；测试程序尝试 7892/7980/18484/公网 IPv4 TCP 均返回 WSAEACCES 10013。
- 界面点击重连成功，原选 Wanda 通道恢复，出口 192.248.188.234。
- UDP 本机接收侧测试未收到受限程序发往 127.0.0.1:18485 的数据包。该结果限本机接收侧，不替代公网 UDP 抓包。
- 配置器新增独立核心丢失后的同通道恢复，每次尝试间隔至少 20 秒。显式停止不恢复，不切换第一跳。
- 模拟核心崩溃及启动 Firefox 做新一轮浏览器测试分别被自动审批以 blocked by policy 拦截；未绕过，不能计为通过。
- Claude 保持退出；Code 新增过滤器仍等待本次 Windows 管理员提权完成，完整 Code 会话未验收。

## 2026-11-05 界面整合更正

独立面板已替换为主界面的应用规则表，共用一个上游选择和应用/重连动作；底层保留德国专用核心以执行固定出口规则。“启动 Claude”已从界面删除，“查看 Claude 本机连接”纯本机只读。整合测试与部署范围见主 README。此前 Code 补装过滤器的管理员提示最终被取消，未完成安装；不能表述为仍在等待或已经覆盖。
