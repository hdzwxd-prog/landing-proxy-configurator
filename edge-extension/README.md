# Edge 会话接入（2026-11-24 已在日常 Edge 验收开关）

系统代理由 Windows / 用户选择的 Clash、Wanda 管理。本扩展不设置它们。
扩展只在配置器本次运行明确请求时，通过浏览器 proxy API 设置自己的覆盖项。
配置器退出/崩溃、通信桥断开时撤销该覆盖项；不是写成 system，也不是自行选择另一个代理。
Firefox / Claude 的德国断网保护独立保留。

本机是 AD 域成员，使用微软支持的本地签名扩展安装策略，无需开发者模式：

1. 构建项目后运行 `Package-LocalExtension.ps1`，将签名包及本机通信桥部署到 LocalAppData。
2. 管理员运行 `Install-LocalPolicy.ps1`，只添加本扩展的安装策略，保留已有策略。
3. Edge 加载策略后，配置器收到实际扩展确认才启用开关。
4. 卸载时管理员运行 `Remove-LocalPolicy.ps1`；只移除匹配所有权记录的单项策略。

签名私钥留在 LocalAppData/EdgeSession/package.pem，ACL 仅当前用户可访问，不提交 Git。
该方案仅用于域成员设备，非域成员不能沿用静默安装结论。

2026-11-24 日常 Edge 实测：关闭时 140.245.46.71，开启时所选 NAS04 212.121.132.230，关闭后恢复 140.245.46.71；系统代理仍为 Wanda 7892。扩展使用普通落地 18484，Claude 登录独立使用 Firefox/德国 18485。

非域设备的开发测试安装需要 Edge 扩展权限（proxy、privacy、nativeMessaging、alarms）：

1. 构建项目。将本目录作为开发阶段未打包扩展，在 Edge 的扩展管理页加载。
2. 复制该扩展的 ID，运行
   `powershell -File edge-extension/Install-NativeHost.ps1 -ExtensionId <ID>`。
   安装器仅注册当前用户的本机通信桥，不写代理策略、不创建自启任务。
3. 点击扩展图标重新连接。配置器确认连接后，才选择 Edge 接入。
4. “浏览器已接受设置”不等于实际出口验证。还须做真实浏览器验收。

此候选版本不能用旧的“Configure-Edge-Landing Enable”安装：
该入口已拒绝新增永久策略。旧策略只提供显式 Restore 迁移，不能覆盖组织策略。
不需要扩展的 Claude/Firefox 仍使用已有专用入口和隔离规则。

扩展权限仅作用于安装它的 Edge 配置；未安装的配置及默认未获授权的
InPrivate 不在声明覆盖范围。扩展不读取网页、Cookie、账号或订阅。
看门狗使用浏览器本地定时事件，睡眠/浏览器冻结时可能延迟，不承诺硬实时恢复。

参考：
- https://developer.chrome.com/docs/extensions/reference/api/proxy
- https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
- https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle
