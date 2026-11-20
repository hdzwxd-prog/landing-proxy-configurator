# 2026-11-20 当前 Claude 版本保护补装验收

用户明确授权补装后，管理员运行已审查的 Update-CodeIsolation.ps1，使用 ensure 事务追加规则，未调用清空/重建安装路径。

- 桌面版本 6.6395.0.0；Code 2.1.325 与 2.1.326。
- 实际阻断谓词读回 verified_applications=25，persistent_filters=147（原 107）。
- 无账号测试程序可连允许的 18485；到 7892、7980、18484、公网 IPv4 TCP、IPv6 loopback 均返回 WSAEACCES 10013。
- 使用无人监听的 18685 模拟入口缺失：连接拒绝；普通代理、其他入口及公网 IPv4 TCP 仍被阻断。
- 本机 UDP 接收端未收到受限测试程序的数据；UDP sendto 返回成功本身不证明送达。公网 UDP 未做接收侧验证，公网 IPv6 返回 10051（无路由），不计为实际阻断证明。
- 真实德国服务未停止，Claude 未启动；7980/18484/18485 PID 均保持不变，德国出口实测 192.248.188.234。

该结论覆盖当前核验路径及规则行为，不覆盖任意 shell/Python/Node 子进程或未来升级路径，不冒充真实 Claude 会话断路实测。升级自动维护机制仍未完成。

本机完整报告保存在 StrictGermany/code-isolation-update.json 和 code-isolation-probe-results.json，不包含账号测试。
