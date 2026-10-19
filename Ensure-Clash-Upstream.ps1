param([Parameter(Mandatory=$true)][string]$Endpoint)
$ErrorActionPreference='Stop'
$routerDir = Join-Path $env:USERPROFILE '.ssh\GermanyRouter'
$endpointFile = Join-Path $routerDir 'clash-upstream.txt'
$endpoint = $Endpoint.Trim() -replace '^https?://',''
$parts = $endpoint.Split(':')
$port=0
if($parts.Count -ne 2 -or [string]::IsNullOrWhiteSpace($parts[0]) -or -not [int]::TryParse($parts[1],[ref]$port) -or $port -lt 1 -or $port -gt 65535){ throw 'Clash 接口格式应为 host:port' }
Set-Content -LiteralPath $endpointFile -Value ($parts[0]+':'+$port) -Encoding ascii
$files = @((Join-Path $routerDir 'config-foreign.yaml'),(Join-Path $routerDir 'config-global.yaml'))
foreach($file in $files){
  if(-not (Test-Path $file)){continue}
  $lines=[Collections.Generic.List[string]]::new()
  $raw=[IO.File]::ReadAllLines($file)
  $inserted=$false; $i=0
  while($i -lt $raw.Count){
    $line=$raw[$i]
    if($line -match '^(\s*)-\s+name:\s+Clash-Upstream\s*$'){
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
      $inserted=$true
    }
    if($line -match '^(\s*)-\s+name:\s+FIRST-HOP\s*$'){
      $indent=$Matches[1]
      $lines.Add("${indent}- name: FIRST-HOP"); $lines.Add("${indent}  type: select"); $lines.Add("${indent}  proxies:"); $lines.Add("${indent}  - Clash-Upstream"); $lines.Add("${indent}  - Wanda-Upstream")
      $i++
      while($i -lt $raw.Count -and $raw[$i] -notmatch '^\s*-\s+name:\s+' ){ $i++ }
      continue
    }
    $lines.Add($line); $i++
  }
  if(-not $inserted){ throw "Germany-VLESS not found in $file" }
  [IO.File]::WriteAllLines($file,$lines,(New-Object Text.UTF8Encoding($false)))
}
Write-Output "clash_endpoint=$($parts[0]):$port"
