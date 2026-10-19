param(
 [Parameter(Mandatory=$true)][ValidateSet('clash','wanda','bigairport')][string]$Choice,
 [string]$Endpoint = '127.0.0.1:7980'
)
$ErrorActionPreference='Stop'
$routerDir=Join-Path $env:USERPROFILE '.ssh\GermanyRouter'
$choiceFile=Join-Path $routerDir 'upstream-choice.txt'
$healthFile=Join-Path $routerDir 'upstream-health.txt'
$secretFile=Join-Path $routerDir 'controller-secret.txt'
$ensure=Join-Path $routerDir 'Ensure-Clash-Upstream.ps1'
$controller='http://127.0.0.1:19090'
$previous=if(Test-Path $choiceFile){(Get-Content $choiceFile -Raw).Trim().ToLowerInvariant()}else{'clash'}
if($previous -notin @('clash','wanda','bigairport')){$previous='clash'}
if($Choice -eq 'clash'){
  & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $ensure -Endpoint $Endpoint | Out-Null
}
$headers=@{}
if(Test-Path $secretFile){$headers=@{Authorization='Bearer '+(Get-Content $secretFile -Raw).Trim()}}
if(Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 19090 -State Listen -ErrorAction SilentlyContinue){
  $target=if($Choice -eq 'clash'){'Clash-Upstream'}elseif($Choice -eq 'wanda'){'Wanda-Upstream'}else{'BigAirport-SG'}
  $body=@{name=$target}|ConvertTo-Json -Compress
  $encoded=[Uri]::EscapeDataString('FIRST-HOP')
  Invoke-RestMethod -UseBasicParsing -Method Put -Uri "$controller/proxies/$encoded" -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 5|Out-Null
  Start-Sleep -Seconds 2
  try{
    $request=[Net.HttpWebRequest]::Create('https://api.ipify.org');$request.Proxy=New-Object Net.WebProxy('http://127.0.0.1:18484');$request.Timeout=10000
    $response=$request.GetResponse();$reader=New-Object IO.StreamReader($response.GetResponseStream());$exitIp=$reader.ReadToEnd().Trim();$reader.Dispose();$response.Dispose()
    if($exitIp -notin @('192.248.188.234','2a05:f480:1800:2d04:5400:5ff:fe92:1848')){throw "unexpected exit $exitIp"}
  }catch{
    $rollback=if($previous -eq 'clash'){'Clash-Upstream'}elseif($previous -eq 'wanda'){'Wanda-Upstream'}else{'BigAirport-SG'}
    try{$body=@{name=$rollback}|ConvertTo-Json -Compress;Invoke-RestMethod -UseBasicParsing -Method Put -Uri "$controller/proxies/$encoded" -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 5|Out-Null}catch{}
    throw "new first hop failed Germany-exit validation; restored $previous"
  }
}
Set-Content -LiteralPath $choiceFile -Value $Choice -Encoding ascii
$active=if($Choice -eq 'clash'){'Clash-Upstream'}elseif($Choice -eq 'wanda'){'Wanda-Upstream'}else{'BigAirport-SG'}
Set-Content -LiteralPath $healthFile -Encoding utf8 -Value @("timestamp=$([DateTime]::Now.ToString('s'))",'state=manual',"active=$active",'node=','delay_ms=-1','reason=manual Clash-compatible interface selection')
Write-Output "choice=$Choice"
