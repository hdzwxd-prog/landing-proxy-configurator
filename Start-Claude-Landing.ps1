param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
$ErrorActionPreference='Stop'
$proxy='http://127.0.0.1:18484'
if(-not (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 18484 -State Listen -ErrorAction SilentlyContinue)){throw '落地代理未运行，请先打开落地代理配置器并选择“仅 Claude/浏览器”。'}
$env:HTTP_PROXY=$proxy; $env:HTTPS_PROXY=$proxy; $env:ALL_PROXY=$proxy
& claude @Arguments
exit $LASTEXITCODE
