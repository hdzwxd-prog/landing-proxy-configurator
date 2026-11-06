$ErrorActionPreference='Stop'
# Bounded metadata trace, no packet capture, browser automation, proxy changes or app requests.
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(-not [Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw '连接失败证据需要管理员读取 ETW；未执行提权或修改。请显式以管理员运行本脚本。'
}
$folder=Join-Path $env:LOCALAPPDATA ('LandingProxyConfigurator\Diagnostics\EdgeTrace-'+(Get-Date -Format yyyyMMdd-HHmmss))
New-Item -ItemType Directory -Path $folder | Out-Null
$network=@(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
  Where-Object {$_.CommandLine -match 'network.mojom.NetworkService'} |
  ForEach-Object {@{pid=[int]$_.ProcessId;started=$_.CreationDate.ToUniversalTime().ToString('o')}})
$name='LandingEdge-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$etl=Join-Path $folder 'connections.etl'
$xml=Join-Path $folder 'connections.xml'
& logman.exe start $name -p Microsoft-Windows-Winsock-AFD 0xffffffffffffffff 5 -o $etl -ets | Out-File (Join-Path $folder 'start.log')
if($LASTEXITCODE -ne 0){throw 'ETW 未启动；没有停止其他会话。'}
try{Start-Sleep -Seconds 12}
finally {& logman.exe stop $name -ets | Out-File (Join-Path $folder 'stop.log')}
& tracerpt.exe $etl -o $xml -of XML -y | Out-File (Join-Path $folder 'convert.log')
if($LASTEXITCODE -ne 0){throw '无法解析 ETW；未得出网络结论。'}
[xml]$events=Get-Content -LiteralPath $xml -Raw
$ns=[Xml.XmlNamespaceManager]::new($events.NameTable)
$ns.AddNamespace('e','http://schemas.microsoft.com/win/2004/08/events/event')
$pending=@{};$attempts=@()
foreach($event in $events.SelectNodes('//e:Event',$ns)) {
    $processId=[int]$event.System.Execution.ProcessID
    if($processId -notin @($network|ForEach-Object {$_.pid})){continue}
    $data=@{};foreach($v in $event.EventData.Data){$data[$v.Name]=([string]$v.'#text').Trim()}
    $task=[string]$event.RenderingInfo.Task
    $key="$processId|$($data.Endpoint)"
    if($task -eq 'AfdConnectWithAddress') {
        $pending.Remove($key)
        if($data.Address -match '^127\.0\.0\.1:(\d+)$'){$pending[$key]=[int]$Matches[1]}
    } elseif($task -eq 'AfdConnect' -and $data.EnterExit -eq '1' -and $pending.ContainsKey($key)) {
        $attempts+=@{pid=$processId;port=$pending[$key];status=$data.Status}
        $pending.Remove($key)
    }
}
$path=Join-Path $folder 'edge-evidence.json'
@{capturedAt=[DateTime]::UtcNow.ToString('o');networkProcesses=$network;attempts=$attempts} |
  ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
& (Join-Path $PSScriptRoot 'Get-LandingDiagnostics.ps1') -EvidencePath $path
Write-Output '原始 ETW 留在本机；分享时只使用脱敏 network 报告。无请求时不会判定通过。'
