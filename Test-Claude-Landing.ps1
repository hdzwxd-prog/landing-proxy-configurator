param([string]$ReportPath = (Join-Path $env:USERPROFILE '.ssh\GermanyRouter\claude-client-check.json'))
$ErrorActionPreference='Stop'
$strict=Test-Path (Join-Path $env:USERPROFILE '.ssh\GermanyRouter\StrictGermany\isolation-install.json')
$expectedPort=if($strict){18485}else{18484}
$processes=@(Get-CimInstance Win32_Process -Filter "Name='Claude.exe'")
$connections=@(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object {$_.OwningProcess -in $processes.ProcessId})
$landing=@($connections | Where-Object {$_.RemoteAddress -in @('127.0.0.1','::1') -and $_.RemotePort -eq $expectedPort})
$otherProxy=@($connections | Where-Object {$_.RemoteAddress -in @('127.0.0.1','::1') -and $_.RemotePort -ne $expectedPort -and $_.RemotePort -in @(7890,7892,7980,18484,18485)})
$external=@($connections | Where-Object {$_.RemoteAddress -notin @('127.0.0.1','::1')})
$state='unverified'
$text='Claude：本次未观察到代理连接，不能判定已受保护。此检查只读，不发起联网。'
if (-not $processes.Count) {$text='Claude：未运行，尚未验证客户端连接。'}
elseif ($otherProxy.Count -or $external.Count) {$state='bypass';$text='Claude：发现其他代理或非回环连接；需检查目标及隔离规则，不能判定已受保护。'}
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
