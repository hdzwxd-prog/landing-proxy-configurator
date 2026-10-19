param(
    [Parameter(Mandatory=$true)][ValidateSet('germany','nas04')][string]$Choice,
    [string]$RouterDir = (Join-Path $env:USERPROFILE '.ssh\GermanyRouter'),
    [int]$ControllerPort = 19090,
    [int]$ProxyPort = 18484,
    [int]$SocksPort = 18583,
    [int]$TransportPort = 18584
)
$ErrorActionPreference = 'Stop'
$controller = "http://127.0.0.1:$ControllerPort"
$runtimeScripts = if (Test-Path (Join-Path $PSScriptRoot 'Start-NAS04-Socks.ps1')) { $PSScriptRoot } else { Split-Path $PSScriptRoot -Parent }
. (Join-Path $PSScriptRoot 'Landing.Common.ps1')
$mutex = [Threading.Mutex]::new($false, "Local\LandingRouteChange$ControllerPort")
if (-not (Enter-LandingChange $mutex 25000)) { throw '另一个链路操作正在进行，请稍后重试。' }
$previous = Get-LandingChoice
$changed = $false
try {
    $mode = if (Test-Path (Join-Path $routerDir 'mode.txt')) { (Get-Content (Join-Path $routerDir 'mode.txt') -Raw).Trim() } else { 'off' }
    if ($mode -eq 'off') {
        Set-Content (Join-Path $routerDir 'landing-choice.txt') $Choice -Encoding ascii
        Write-LandingHealth $Choice 'idle' 'saved; enable a routing mode to connect'
        Write-Output 'saved (not connected)'
        exit 0
    }
    Ensure-LandingRuntime
    if ($Choice -eq 'nas04') { Ensure-Nas04Socks $SocksPort $TransportPort }
    Set-LandingGroup 'LANDING' (Get-LandingTarget $Choice)
    $changed = $true
    if (-not (Test-LandingExit $Choice $ProxyPort)) { throw '所选落地出口检测失败' }
    Set-Content (Join-Path $routerDir 'landing-choice.txt') $Choice -Encoding ascii
    Write-LandingHealth $Choice 'healthy' "exit=$script:verifiedExit"
    if ($Choice -ne 'nas04') { Stop-Nas04Socks }
    Write-Output "landing=$Choice; exit=$script:verifiedExit"
} catch {
    $failure = $_.Exception.Message
    $rollbackOk = -not $changed
    if ($changed) {
        try { Set-LandingGroup 'LANDING' (Get-LandingTarget $previous); $rollbackOk = $true } catch { }
    }
    if ($previous -ne 'nas04') { Stop-Nas04Socks }
    if ($rollbackOk) {
        Write-LandingHealth $previous 'pending' 'selection failed; previous landing restored; recheck exit'
        throw "$failure；已保留原落地选择。"
    }
    Write-LandingHealth $previous 'degraded' 'selection and rollback failed; reconnect required'
    throw "$failure；回滚失败，请重新连接。"
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
