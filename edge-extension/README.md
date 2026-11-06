# Edge 会话接入（候选功能，真实浏览器验收待完成）

系统代理由 Windows / 用户选择的 Clash、Wanda 管理。本扩展不设置它们。
扩展只在配置器本次运行明确请求时，通过浏览器 proxy API 设置自己的覆盖项。
配置器退出/崩溃、通信桥断开时撤销该覆盖项；不是写成 system，也不是自行选择另一个代理。
Firefox / Claude 的德国断网保护独立保留。

一次性安装需要 Edge 扩展权限（proxy、privacy、nativeMessaging、alarms）：

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
