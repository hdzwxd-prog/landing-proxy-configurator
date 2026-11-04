# 独立德国严格入口（实施中，尚未完成系统阻断验收）

这组工具用于 Firefox 和 Claude 的固定德国出口，与可切换的通用 18484 入口分开。
18485 仅有 MATCH,Germany-VLESS，没有 DIRECT、NAS04、可变出口组或控制接口。
第一跳是明确选择的本机 HTTP/mixed 端口，没有自动选路。

`StrictNetworkLock.cpp` 使用 Windows 原生 WFP 持久过滤器，按应用路径和 Claude 包身份限定连接。
候选规则仅允许应用连接 TCP 127.0.0.1:18485，核心只允许连接指定第一跳。
过滤器写入使用事务，只替换本工具自己的 provider；删除需要显式执行管理命令。
**这些过滤器尚未在目标机通过管理员安装和运行验证，不应作为已生效保护使用。**
需验证 Firefox/Claude 本机 IPC 与严格 loopback 过滤的兼容性，再决定最终规则。
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

## 2026-11-04 当前验证

- Mozilla 官方 Firefox 159.0.1 安装包 Authenticode 签名 Valid，签名者 Mozilla Corporation。
- 安装位置为 `%LOCALAPPDATA%/Programs/Mozilla Firefox`。
- 通过实际 Firefox Marionette 读取生效策略和锁定首选项，代理为 18485，WebRTC/HTTP3/直连回退关闭。
- 停止 18485 后，实际 Firefox 新导航收到 `proxyConnectFailure`，未回退访问测试网页。
- 启动阶段曾观测到 Firefox socket 进程的一条公网 TCP 443 连接，尚未定位请求来源；仅有浏览器策略不能作为系统级全流量约束的验收依据。
- 当前 Clash 7980 到德国 TLS 握手失败，Wanda 7892 到德国 TLS 握手成功。尚未授权切换专用第一跳，未做切换。
- Windows 管理员提权返回用户取消。WFP 规则尚未安装，Claude 严格管理策略尚未写入，也未重启 Claude。
- 尚未验证 Firefox 成功德国出口、WFP 直连/其他代理/IPv6/UDP 阻断、Claude 实际路由与故障恢复。
- 测试后退出 Firefox，关闭 Marionette，停止仅本次新建的 18485 核心。原网络保持不变。

只有上述剩余项实测通过后才能把“实施中”改为交付状态。固定出口不证明账号封禁原因，也不保证不会触发服务方账号限制。
