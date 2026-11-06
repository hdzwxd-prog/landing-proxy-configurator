# 落地代理配置器 0.2

本软件只管理独立落地服务，不写 Windows 系统代理，不控制 Clash/Wanda 的进程、订阅、节点或系统代理开关。
不开本软件时，普通网络由 Windows 和你自行启动的上游客户端管理。

## 当前边界

| 对象 | 谁管理 | 退出/故障行为 |
|---|---|---|
| 系统代理、Codex、普通应用 | Windows / 用户的 Clash 或 Wanda | 本软件不修改，不恢复旧快照 |
| 独立常规落地入口 18484 | 本软件 | 服务停止后不可用 |
| Edge 可选落地 | Edge 会话扩展 + 配置器的本机连接 | 退出/连接断开撤销扩展自己的代理覆盖；不设置普通上游 |
| Firefox / Claude 德国入口 18485 | 德国专用核心 + 已安装应用隔离 | 入口不可用则受保护程序断网；不因 Edge 退出而解锁 |

所有流量规则仅作用于明确接入本软件的应用，不再提供修改系统代理的“全局模式”。
选择 Clash/Wanda 是选择第一跳接口；订阅、节点仍在它们自己的客户端内选择。
常规落地可选德国或 NAS04；Firefox / Claude 始终固定德国，不跟随常规出口切到 NAS04。

## 日常使用

1. 自己打开需要的 Clash 或 Wanda，选好节点。
2. 启动桌面唯一入口“落地代理配置器.exe”。选择上游，再启用需要的落地流量模式并应用设置。
3. Firefox / Claude 使用已有德国专用代理和系统隔离；本软件不代为启动 Claude。
4. Edge 保留可选接入，但 0.2 使用新的会话扩展，不再写永久代理策略。
   **扩展真实浏览器验收尚未完成；未安装/未确认连接时不能视为 Edge 已接入。**
   一次性安装步骤见 [Edge 接入说明](edge-extension/README.md)。
5. × 收进托盘；彻底退出停止本软件的服务。Edge 撤销接管，Firefox / Claude 保留断网保护。

“已写入”“端口监听”“服务出口通过”“浏览器已接受设置”“浏览器出口通过”是不同证据。
任何一个都不能单独证明所有应用请求均已保护。新版本启动默认不请求 Edge 接入。
既有 TCP 连接不能无缝迁移；浏览器完全冻结时事件处理可能延迟。

Claude Code 的现有原生引擎路径有独立规则；任意终端/Python/Node 子进程及未来新路径不在全部覆盖声明内。
保护范围和无账号验收见 [strict/README.md](strict/README.md)。

## 诊断和复盘

[2026-11-06 事故复盘](docs/2026-11-06-incident.md) 区分事实、误判、根因、修正和剩余验收。

- 界面“导出网络诊断（只读）”：不访问网站，不启动 Claude，不读取密钥、订阅或账号。
- CLI：`powershell -File diagnostics/Get-LandingDiagnostics.ps1`。
- 失败请求不明时，显式以管理员运行 `diagnostics/Trace-EdgeConnections.ps1`：
  采集 12 秒连接元数据，匹配 Edge 网络 PID、创建时间及证据时效。不自动打开网页、不抓数据包。
- 结果在 `%LOCALAPPDATA%/LandingProxyConfigurator/Diagnostics`。只分享脱敏 network 报告，原始跟踪留在本机。
- 没有请求证据就是未验证。别的进程被拦截不能归因给 Edge。

## 源码、构建和发布

源码在本仓库；桌面只保留当前 EXE。构建运行 `powershell -File Build.ps1`，产物在 `bin/`。
运行脚本在 `%USERPROFILE%/.ssh` 和 `.ssh/GermanyRouter`；密钥、运行配置、日志和会话备份不入 Git。
桌面/脚本升级前备份到 `%LOCALAPPDATA%/LandingProxyConfigurator/Archive` 并保存 SHA256 清单。

禁止将未通过真实浏览器验收的 Edge 会话功能宣称为完整交付。
部署到现有运行环境时先核对旧持久策略；必要迁移必须显式处理，不能自动覆盖组织策略。
旧 `Configure-Edge-Landing.ps1` 只保留 Restore/Status 迁移路径，Enable 已拒绝新增永久策略。
自启保持禁用；构建和部署不重新注册或开启计划任务。

## 离线验证

- `node --test tests/test_edge_session.mjs`
- `python tests/test_native_host.py`
- `python tests/test_no_system_proxy_writes.py`
- `python tests/test_integrated_route.py`
- `python tests/test_strict_config.py`
- `powershell -File tests/test_edge_policy.ps1`（隔离测试注册表项）
- `powershell -File tests/test_diagnosis.ps1`
- `powershell -File tests/test_stop_boundary.ps1`（隔离目录与模拟进程）
- `tests/EdgeLeaseTest.cs`：随机命名管道，不接入真实浏览器。

上述测试不等于真实浏览器、真实账号或电脑重启验收。
