param([string]$EvidencePath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Diagnosis.Common.ps1')
function LocalPort($value) {
    if([string]$value -match '(?:127\.0\.0\.1|localhost):(\d{1,5})'){return [int]$Matches[1]}
    return 0
}
function Read-BlobProxy([byte[]]$bytes) {
    if(-not $bytes -or $bytes.Length -lt 20){return $null}
    $length=[BitConverter]::ToInt32($bytes,12)
    if($length -lt 0 -or 20+$length -gt $bytes.Length){return $null}
    $offset=16+$length;$bypassLength=[BitConverter]::ToInt32($bytes,$offset)
    if($bypassLength -lt 0 -or $offset+4+$bypassLength -gt $bytes.Length){return $null}
    return @{server=[Text.Encoding]::UTF8.GetString($bytes,16,$length);
      bypass=[Text.Encoding]::UTF8.GetString($bytes,$offset+4,$bypassLength)}
}
$internet='HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$settings=Get-ItemProperty $internet
$blob=Read-BlobProxy (Get-ItemProperty ($internet+'\Connections')).DefaultConnectionSettings
$policy=Get-ItemProperty 'HKCU:\Software\Policies\Microsoft\Edge' -ErrorAction SilentlyContinue
$processes=@(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'")
$networkPids=@($processes|Where-Object {$_.CommandLine -match 'network.mojom.NetworkService'}|ForEach-Object {[int]$_.ProcessId})
$allPids=@($processes|ForEach-Object {[int]$_.ProcessId})
$readSucceeded=$true
try {$tcp=@(Get-NetTCPConnection -ErrorAction Stop)}catch{$tcp=@();$readSucceeded=$false}
$attempts=@()
if($EvidencePath) {
    $evidence=Get-Content -LiteralPath $EvidencePath -Raw|ConvertFrom-Json
    $age=([DateTime]::UtcNow-[DateTime]::Parse($evidence.capturedAt).ToUniversalTime()).TotalSeconds
    if($age -lt 0 -or $age -gt 60){throw 'ETW 证据已过期；不能用于当前结论。'}
    $verifiedIds=@($processes|Where-Object {
      $p=$_
      @($evidence.networkProcesses|Where-Object {
        $_.pid -eq $p.ProcessId -and [DateTime]::Parse($_.started).ToUniversalTime() -eq $p.CreationDate.ToUniversalTime()
      }).Count -gt 0
    }|ForEach-Object {[int]$_.ProcessId})
    $attempts=@($evidence.attempts|Where-Object {$_.pid -in $verifiedIds})
}
$snapshot=[ordered]@{
    timestamp=[DateTime]::UtcNow.ToString('o')
    systemProxyEnabled=([int]$settings.ProxyEnable -eq 1)
    systemProxyPort=$(if($settings.ProxyEnable){LocalPort $settings.ProxyServer}else{0})
    effectiveProxyPort=$(if($blob){LocalPort $blob.server}else{0})
    proxyRepresentationsDiffer=([bool]$blob -and ($blob.server -cne [string]$settings.ProxyServer -or $blob.bypass -cne [string]$settings.ProxyOverride))
    edgePolicyPort=(LocalPort $policy.ProxySettings)
    edgeNetworkPids=$networkPids
    edgeProcesses=@($processes|ForEach-Object {@{pid=[int]$_.ProcessId;started=$_.CreationDate.ToUniversalTime().ToString('o');startupBoost=($_.CommandLine -match '--no-startup-window')}})
    connectionReadSucceeded=$readSucceeded
    listeningPorts=@($tcp|Where-Object {$_.State -eq 'Listen' -and $_.LocalPort -in @(7892,7980,18484,18485)}|ForEach-Object {[int]$_.LocalPort}|Sort-Object -Unique)
    edgeEstablishedPorts=@($tcp|Where-Object {$_.OwningProcess -in $allPids -and $_.State -eq 'Established' -and $_.RemoteAddress -eq '127.0.0.1'}|ForEach-Object {[int]$_.RemotePort}|Sort-Object -Unique)
    edgeConnectAttempts=$attempts
    startup=@(Get-ScheduledTask -TaskName 'Germany Proxy Manager Tray','Germany Rule Router 18484','Germany SOCKS Tunnel 18483','Germany Proxy Cleanup At Logon' -ErrorAction SilentlyContinue|ForEach-Object {@{name=$_.TaskName;state=$_.State.ToString()}})
}
$report=[ordered]@{snapshot=$snapshot;findings=@(Get-LandingFindings ([pscustomobject]$snapshot));
  limits='只读快照，不访问外网或 Claude；无连接不等于健康。未读取密钥、订阅、Cookie、网页内容或完整命令行。'}
$folder=Join-Path $env:LOCALAPPDATA 'LandingProxyConfigurator\Diagnostics'
New-Item -ItemType Directory -Force -Path $folder|Out-Null
$path=Join-Path $folder ('network-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.json')
$report|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
Set-Content -LiteralPath (Join-Path $folder 'latest.txt') -Value (@($report.findings)+@('报告：'+$path,$report.limits)) -Encoding UTF8
Write-Output $path
