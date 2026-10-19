param([string]$ReportPath = (Join-Path $env:USERPROFILE '.ssh\GermanyRouter\claude-client-check.json'))
$ErrorActionPreference='Stop'
$processes=@(Get-CimInstance Win32_Process -Filter "Name='Claude.exe'")
$connections=@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object {$_.OwningProcess -in $processes.ProcessId})
$landing=@($connections | Where-Object {$_.RemoteAddress -in @('127.0.0.1','::1') -and $_.RemotePort -eq 18484})
$otherProxy=@($connections | Where-Object {$_.RemoteAddress -in @('127.0.0.1','::1') -and $_.RemotePort -in @(7890,7892,7980)})
$external=@($connections | Where-Object {$_.RemoteAddress -notin @('127.0.0.1','::1')})
$state='unverified'
$text='Claude：当前无可核对的落地连接；请重开客户端并刷新。'
if (-not $processes.Count) {$text='Claude：未运行，尚未验证客户端连接。'}
elseif ($otherProxy.Count -or $external.Count) {$state='bypass';$text='Claude：发现未走落地的连接，请完整退出并用“启动 Claude 客户端”重开。'}
elseif ($landing.Count) {$state='observed';$text='Claude：本次观察到 '+$landing.Count+' 条落地连接；不代表所有功能均已验证。'}
$report=[pscustomobject]@{
    timestamp=[DateTime]::UtcNow.ToString('o');state=$state;message=$text
    landingConnections=$landing.Count;otherProxyConnections=$otherProxy.Count;externalConnections=$external.Count
    processes=@($processes | Select-Object ProcessId,ParentProcessId)
    connections=@($connections | Select-Object OwningProcess,RemoteAddress,RemotePort)
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Set-Content -LiteralPath ([IO.Path]::ChangeExtension($ReportPath,'.txt')) -Value $text -Encoding UTF8
Write-Output $text
