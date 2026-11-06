param([Parameter(Mandatory)][ValidatePattern('^[a-p]{32}$')][string]$ExtensionId)
$ErrorActionPreference='Stop'
# Explicit installation only. No Edge policy, Internet Settings, startup task, or app restart.
$exe=Join-Path $PSScriptRoot '..\bin\LandingEdgeNativeHost.exe'
if(-not (Test-Path -LiteralPath $exe)){throw '请先构建项目。'}
$target=Join-Path $env:LOCALAPPDATA 'LandingProxyConfigurator\EdgeSession'
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -LiteralPath $exe -Destination (Join-Path $target 'LandingEdgeNativeHost.exe')
$manifest=Join-Path $target 'native-host.json'
$content=@{name='local.landing_proxy.session';description='Landing proxy session';
  path=(Join-Path $target 'LandingEdgeNativeHost.exe');type='stdio';
  allowed_origins=@("chrome-extension://$ExtensionId/")} |
  ConvertTo-Json
[IO.File]::WriteAllText($manifest,$content,[Text.UTF8Encoding]::new($false))
$key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\Microsoft\Edge\NativeMessagingHosts\local.landing_proxy.session')
try{$key.SetValue('',$manifest)}finally{$key.Close()}
Write-Output '已注册当前用户的本机通信桥；未修改代理。请在 Edge 扩展中点击重新连接。'
