param([Parameter(Mandatory=$true)][string]$Endpoint, [string]$RouterDir = (Join-Path $env:USERPROFILE '.ssh\GermanyRouter'), [int]$SocksPort=18583, [int]$TransportPort=18584, [int]$ProxyPort=18484, [int]$ControllerPort=19090)
$ErrorActionPreference='Stop'
$endpointFile = Join-Path $routerDir 'clash-upstream.txt'
$endpoint = $Endpoint.Trim() -replace '^https?://',''
$parts = $endpoint.Split(':')
$port=0
if($parts.Count -ne 2 -or $parts[0] -notmatch '^[a-zA-Z0-9.-]+$' -or -not [int]::TryParse($parts[1],[ref]$port) -or $port -lt 1 -or $port -gt 65535){ throw 'Clash 接口格式应为 host:port' }
if ($parts[0] -notin @('127.0.0.1','localhost')) { throw '上游必须是本机代理接口：127.0.0.1:端口。' }
if ($port -in @($ProxyPort,$ControllerPort,$SocksPort,$TransportPort)) { throw '不能将落地自身端口设为上游，否则会形成代理回环。' }
Set-Content -LiteralPath $endpointFile -Value ($parts[0]+':'+$port) -Encoding ascii
$files = @((Join-Path $routerDir 'config-foreign.yaml'),(Join-Path $routerDir 'config-global.yaml'))
foreach($file in $files){
  if(-not (Test-Path $file)){continue}
  $lines=[Collections.Generic.List[string]]::new()
  $raw=[IO.File]::ReadAllLines($file)
  $inserted=$false; $i=0
  while($i -lt $raw.Count){
    $line=$raw[$i]
    if($line -match '^(\s*)-\s+name:\s+(Clash-Upstream|NAS04-SSH)\s*$'){
      $indent=$Matches[1]; $i++
      while($i -lt $raw.Count -and $raw[$i] -notmatch '^\s*-\s+name:\s+' -and $raw[$i] -notmatch '^\s*proxy-groups\s*:'){ $i++ }
      continue
    }
    if(-not $inserted -and $line -match '^(\s*)-\s+name:\s+Germany-VLESS\s*$'){
      $indent=$Matches[1]
      $lines.Add("${indent}- name: Clash-Upstream")
      $lines.Add("${indent}  type: http")
      $lines.Add("${indent}  server: $($parts[0])")
      $lines.Add("${indent}  port: $port")
      $lines.Add("${indent}  udp: false")
      $lines.Add("${indent}- name: NAS04-SSH")
      $lines.Add("${indent}  type: socks5")
      $lines.Add("${indent}  server: 127.0.0.1")
      $lines.Add("${indent}  port: $SocksPort")
      $lines.Add("${indent}  udp: false")
      $inserted=$true
    }
    if($line -match '^(\s*)-\s+name:\s+FIRST-HOP\s*$'){
      $indent=$Matches[1]
      $lines.Add("${indent}- name: FIRST-HOP"); $lines.Add("${indent}  type: select"); $lines.Add("${indent}  proxies:"); $lines.Add("${indent}  - Clash-Upstream"); $lines.Add("${indent}  - Wanda-Upstream")
      $i++
      while($i -lt $raw.Count -and $raw[$i] -notmatch '^\s*-\s+name:\s+' -and $raw[$i] -notmatch '^[a-zA-Z][\w-]*:'){ $i++ }
      continue
    }
    if($line -match '^(\s*)-\s+name:\s+(LANDING|BigAirport-SG)\s*$'){
      $i++
      while($i -lt $raw.Count -and $raw[$i] -notmatch '^\s*-\s+name:\s+' -and $raw[$i] -notmatch '^[a-zA-Z][\w-]*:'){ $i++ }
      continue
    }
    if($line -match '^proxy-groups:'){
      $lines.Add($line)
      $groupIndent = ''; if($i+1 -lt $raw.Count -and $raw[$i+1] -match '^(\s*)- name:'){ $groupIndent=$Matches[1] }
      $lines.Add("${groupIndent}- name: LANDING"); $lines.Add("${groupIndent}  type: select"); $lines.Add("${groupIndent}  proxies: [Germany-VLESS, NAS04-SSH]")
      $i++; continue
    }
    if($line -match '^(tunnels|proxy-providers):'){
      $i++
      while($i -lt $raw.Count -and $raw[$i] -notmatch '^[a-zA-Z][\w-]*:'){ $i++ }
      continue
    }
    if($line -match '^proxies:'){
      $lines.Add('tunnels:'); $lines.Add("- tcp,127.0.0.1:$TransportPort,212.121.132.230:22,FIRST-HOP")
    }
    # Terminal route groups reference the selectable exit, not a fixed server.
    $line = $line -replace '^(\s*-\s+)Germany-VLESS\s*$', '${1}LANDING'
    $line = $line -replace 'proxies: \[Germany-VLESS\]', 'proxies: [LANDING]'
    $lines.Add($line); $i++
  }
  if(-not $inserted){ throw "Germany-VLESS not found in $file" }
  [IO.File]::WriteAllLines($file,$lines,(New-Object Text.UTF8Encoding($false)))
}
Write-Output "clash_endpoint=$($parts[0]):$port"
