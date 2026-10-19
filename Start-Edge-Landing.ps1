$ErrorActionPreference='Stop'
$proxy='http://127.0.0.1:18484'
if(-not (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 18484 -State Listen -ErrorAction SilentlyContinue)){throw '落地代理未运行，请先打开落地代理配置器并选择“仅 Claude/浏览器”。'}
$edge=Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
if(-not (Test-Path $edge)){$edge=Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'}
if(-not (Test-Path $edge)){throw '未找到 Microsoft Edge'}
$profile=Join-Path $env:LOCALAPPDATA 'LandingProxyEdgeProfile'
Start-Process -FilePath $edge -ArgumentList @('--proxy-server='+$proxy,'--proxy-bypass-list=<-loopback>','--user-data-dir='+$profile)
