param([switch]$NoDialog)
$ErrorActionPreference = 'Stop'
try {
    . (Join-Path $PSScriptRoot 'App-Landing.Common.ps1')
    Assert-AppLandingReady
    $package = Get-AppxPackage -Name 'Claude' | Sort-Object Version -Descending | Select-Object -First 1
    $exe = if ($package) { Join-Path $package.InstallLocation 'app\Claude.exe' } else { Join-Path $env:LOCALAPPDATA 'AnthropicClaude\Claude.exe' }
    if (-not (Test-Path -LiteralPath $exe)) { throw '未找到 Claude 桌面客户端。' }
    $stateFile = Join-Path $env:USERPROFILE '.ssh\GermanyRouter\claude-landing-config.json'
    $policy = if (Test-Path $stateFile) {Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json} else {$null}
    $config = if ($policy -and (Test-Path $policy.configPath)) {Get-Content $policy.configPath -Raw -Encoding UTF8 | ConvertFrom-Json} else {$null}
    if (-not $policy.enabled -or $config.egressProxyUrl -ne 'http://127.0.0.1:18484' -or $config.egressProxyPacUrl) {
        & (Join-Path $PSScriptRoot 'Configure-Claude-Landing.ps1') -Action Enable
    }
    $running = @(Get-CimInstance Win32_Process -Filter "Name='Claude.exe'" | Where-Object {$_.ExecutablePath -eq $exe -and $_.CommandLine -notmatch '--type='})
    if ($running.Count) {
        $stampFile = Join-Path $env:USERPROFILE '.ssh\GermanyRouter\claude-policy-applied.txt'
        $applied = if (Test-Path $stampFile) {[DateTime]::Parse((Get-Content $stampFile -Raw)).ToUniversalTime()} else {[DateTime]::MaxValue}
        if (@($running | Where-Object {$_.CreationDate.ToUniversalTime() -lt $applied}).Count) {
            throw 'Claude 正在运行，旧进程还没有加载落地设置。请先保存工作，在 Claude 托盘菜单中完全退出，再点击此启动器。不会强制结束你的任务。'
        }
    }
    Set-AppLandingEnvironment
    Start-Process -FilePath $exe -ArgumentList @('--proxy-server=http://127.0.0.1:18484','--disable-quic','--force-webrtc-ip-handling-policy=disable_non_proxied_udp')
} catch {
    if ($NoDialog) { throw }
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Claude 客户端 · 落地代理','OK','Warning') | Out-Null
    exit 1
}
