param([switch]$NoDialog)
$ErrorActionPreference='Stop'
try {
    . (Join-Path $PSScriptRoot 'App-Landing.Common.ps1')
    Assert-AppLandingReady
    $edge=Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'
    if(-not (Test-Path $edge)){$edge=Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'}
    if(-not (Test-Path $edge)){throw '未找到 Microsoft Edge'}
    $profile=Join-Path $env:LOCALAPPDATA 'LandingProxyEdgeProfile'
    $running = @(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" | Where-Object {$_.CommandLine -like '*LandingProxyEdgeProfile*' -and $_.CommandLine -notmatch '--type='})
    if (@($running | Where-Object {$_.CommandLine -notlike '*--force-webrtc-ip-handling-policy=disable_non_proxied_udp*' -or $_.CommandLine -notlike '*--proxy-server=http://127.0.0.1:18484*'}).Count) {
        throw '旧的落地浏览器仍在运行，请关闭它后重试。普通 Edge 窗口不需要关闭。'
    }
    if (-not $running.Count) {Set-EdgeLandingPrivacy $profile}
    else {
        $prefs=Get-Content -LiteralPath (Join-Path $profile 'Default\Preferences') -Raw -Encoding UTF8 | ConvertFrom-Json
        if($prefs.webrtc.ip_handling_policy -ne 'disable_non_proxied_udp') {throw '落地浏览器尚未加载 WebRTC 隐私设置，请关闭其全部窗口后重新启动。'}
    }
    $args = @('--proxy-server=http://127.0.0.1:18484','--proxy-bypass-list=<-loopback>',('--user-data-dir="'+$profile+'"'),'--disable-quic','--force-webrtc-ip-handling-policy=disable_non_proxied_udp','--no-first-run','--no-default-browser-check','https://api.ipify.org')
    Start-Process -FilePath $edge -ArgumentList $args
} catch {
    if ($NoDialog) { throw }
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Edge · 落地代理','OK','Warning') | Out-Null
    exit 1
}
