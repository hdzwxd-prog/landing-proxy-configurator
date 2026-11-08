$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\diagnostics\Diagnosis.Common.ps1')
function Assert($ok,$why){if(-not $ok){throw $why}}
$s=[pscustomobject]@{systemProxyPort=7892;edgePolicyPort=0;proxyRepresentationsDiffer=$false;
  edgeNetworkPids=@(123);listeningPorts=@(7892);edgeEstablishedPorts=@();
  connectionReadSucceeded=$true;edgeConnectAttempts=@()}
Assert ((Get-LandingFindings $s) -match '没有 Edge 请求证据') 'No request must remain unverified'
$s.edgeConnectAttempts=@([pscustomobject]@{pid=999;port=18484;status='0xC0000236'})
Assert (-not ((Get-LandingFindings $s) -match '已确认 Edge')) 'Another process must not be attributed to Edge'
$s.edgeConnectAttempts=@([pscustomobject]@{pid=123;port=18484;status='0xC0000236'})
Assert ((Get-LandingFindings $s) -match '已确认 Edge') 'Actual failed Edge connection should identify the dead port'
$s.listeningPorts=@(7892,18484)
Assert (-not ((Get-LandingFindings $s) -match '已确认 Edge')) 'A live listener must not be called absent'
$s.proxyRepresentationsDiffer=$true
Assert ((Get-LandingFindings $s) -match '不一致') 'Effective settings drift must be visible'
'PASS: unknown state, process attribution, refused dead port, live listener, configuration drift'
$s|Add-Member NoteProperty edgeRequested $false
$s.edgeEstablishedPorts=@(18484)
Assert ((Get-LandingFindings $s) -match '开关关闭') 'Disabled switch must not hide observed landing traffic'
$s.edgeRequested=$null
Assert (-not ((Get-LandingFindings $s) -match '开关关闭')) 'Unknown GUI state must not be called disabled'
'PASS: observed Edge route versus requested state'
