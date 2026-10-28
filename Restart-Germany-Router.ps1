param(
    [string]$RouterDir = (Join-Path $env:USERPROFILE '.ssh\GermanyRouter'),
    [int]$ControllerPort = 19090,
    [int]$ProxyPort = 18484,
    [int]$SocksPort = 18583,
    [int]$TransportPort = 18584,
    [switch]$ReloadConfig
)
$ErrorActionPreference = 'Stop'
$modeFile = Join-Path $routerDir 'mode.txt'
$mode = if (Test-Path $modeFile) { (Get-Content $modeFile -Raw).Trim() } else { 'off' }
if ($mode -notin @('foreign','global','apps')) { Write-Output 'off; no reconnection needed'; exit 0 }
$common = Join-Path $PSScriptRoot 'Landing.Common.ps1'
if (-not (Test-Path $common)) { $common = Join-Path $routerDir 'Landing.Common.ps1' }
. $common
$controller = "http://127.0.0.1:$ControllerPort"
$runtimeScripts = $PSScriptRoot
# Reuse the core and healthy in-flight sessions. Only the independent
# supervisor may recover its own dead core; upstream apps are never controlled.
if ($ControllerPort -eq 19090 -and $routerDir -eq (Join-Path $env:USERPROFILE '.ssh\GermanyRouter')) {
    $supervisorMutex = [Threading.Mutex]::new($false, 'Local\GermanyRuleRouter18484')
    $missing = Enter-LandingChange $supervisorMutex
    if ($missing) { $supervisorMutex.ReleaseMutex() }
    $supervisorMutex.Dispose()
    if ($missing) {
        $start = Join-Path $env:USERPROFILE '.ssh\Start-Germany-Router.ps1'
        Start-Process powershell.exe -WindowStyle Hidden -ArgumentList ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$start+'"') | Out-Null
        for ($i=0; $i -lt 40 -and -not (Test-LandingListener $ControllerPort); $i++) { Start-Sleep -Milliseconds 500 }
    }
}
$mutex = [Threading.Mutex]::new($false, "Local\LandingRouteChange$ControllerPort")
if (-not (Enter-LandingChange $mutex 25000)) { $mutex.Dispose(); throw '另一个链路操作正在进行，请稍后重试。' }
try {
    Invoke-LandingReconnect $ProxyPort $SocksPort $TransportPort ([bool]$ReloadConfig)
    Write-Output "reconnected; exit=$script:verifiedExit"
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
