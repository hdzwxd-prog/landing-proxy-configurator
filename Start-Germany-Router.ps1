param(
    [string]$RouterDir = (Join-Path $env:USERPROFILE '.ssh\GermanyRouter'),
    [int]$ProxyPort = 18484,
    [int]$ControllerPort = 19090,
    [int]$SocksPort = 18583,
    [int]$TransportPort = 18584,
    [switch]$Isolated
)
$productionDir = Join-Path $env:USERPROFILE '.ssh\GermanyRouter'
if ($Isolated) {
    if ($RouterDir -eq $productionDir -or (@($ProxyPort,$ControllerPort,$SocksPort,$TransportPort) | Where-Object { $_ -in @(18484,19090,18583,18584,7892,7980) })) {
        throw 'Isolated supervisor must not use production paths or ports.'
    }
} elseif ($RouterDir -ne $productionDir -or $ProxyPort -ne 18484 -or $ControllerPort -ne 19090 -or $SocksPort -ne 18583 -or $TransportPort -ne 18584) {
    throw 'Non-production supervisor requires -Isolated.'
}
$ErrorActionPreference = 'Continue'
$mutex = [Threading.Mutex]::new($false, "Local\GermanyRuleRouter$ProxyPort")
try { $ownsMutex=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $ownsMutex=$true }
if (-not $ownsMutex) { exit 0 }

$modeFile = Join-Path $routerDir 'mode.txt'
$healthFile = Join-Path $routerDir 'route-health.txt'
$upstreamHealthFile = Join-Path $routerDir 'upstream-health.txt'
$upstreamChoiceFile = Join-Path $routerDir 'upstream-choice.txt'
$supervisorLog = Join-Path $routerDir 'supervisor.log'
$controllerSecretFile = Join-Path $routerDir 'controller-secret.txt'
$stopNas04Script = Join-Path $routerDir '..\Stop-NAS04-Socks.ps1'
$clashEndpointFile = Join-Path $routerDir 'clash-upstream.txt'
$mihomo = Join-Path $routerDir 'landing-router-core.exe'
if (-not (Test-Path $mihomo)) { throw '独立落地核心缺失，请修复安装；不会启动或复制上游客户端。' }
$controller = "http://127.0.0.1:$ControllerPort"
$runtimeScripts = $PSScriptRoot
. (Join-Path $routerDir 'Landing.Common.ps1')
$changeMutex = [Threading.Mutex]::new($false, "Local\LandingRouteChange$ControllerPort")
$routerProcess = $null
$script:lastGermanExit = ''
$routeFailures = 0
$lastNasRecovery = [DateTime]::MinValue
$heartbeatFile = Join-Path $routerDir 'supervisor-heartbeat.txt'

function Write-Health([string]$state, [string]$detail) {
    Set-Content -LiteralPath $healthFile -Encoding utf8 -Value @(
        "timestamp=$([DateTime]::Now.ToString('s'))"
        "state=$state"
        "landing=$(Get-LandingChoice)"
        "detail=$detail"
    )
}

function Write-UpstreamHealth([string]$state, [string]$active, [string]$node, [int]$delay, [string]$reason) {
    Set-Content -LiteralPath $upstreamHealthFile -Encoding utf8 -Value @(
        "timestamp=$([DateTime]::Now.ToString('s'))"
        "state=$state"
        "active=$active"
        "node=$node"
        "delay_ms=$delay"
        "reason=$reason"
    )
}

function Set-FailClosed([string]$reason) {
    Write-Health 'degraded' "$reason; fail_closed=127.0.0.1:18484"
    Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) FAIL-CLOSED $reason; kept=127.0.0.1:18484"
}

function Test-GermanExit {
    $ok = Test-LandingExit (Get-LandingChoice) $ProxyPort
    if ($ok) { $script:lastGermanExit = $script:verifiedExit }
    return $ok
}


try {
    $appliedMode = ''
    $lastRouteHealth = [DateTime]::MinValue
    $lastUpstreamHealth = [DateTime]::MinValue
    $lastCoreStart = [DateTime]::MinValue
    Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) supervisor started; upstream applications unmanaged"
    while ($true) {
        $mode = if (Test-Path $modeFile) { (Get-Content $modeFile -Raw).Trim().ToLowerInvariant() } else { 'off' }
        if ($mode -notin @('foreign','global','apps')) { break }
        if ($Isolated -and $mode -ne 'apps') { throw 'Isolated supervisor only supports apps mode.' }
        Set-Content -LiteralPath $heartbeatFile -Value ([DateTime]::UtcNow.ToString('o')) -Encoding ascii
        if (-not (Enter-LandingChange $changeMutex)) { Start-Sleep -Seconds 2; continue }
        try {
            $configMode = Get-LandingConfigMode $mode
            $existing = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $ProxyPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($existing) {
                $routerProcess = Get-Process -Id $existing.OwningProcess -ErrorAction Stop
                if ($routerProcess.Path -ne $mihomo) { throw '18484 被其他进程占用；不会终止该进程。' }
            } else {
                if ($routerProcess -and -not $routerProcess.HasExited) { throw '落地核心尚未提供监听，保持等待。' }
                if (([DateTime]::Now - $lastCoreStart).TotalSeconds -lt 15) { throw '等待独立核心恢复重试。' }
                $lastCoreStart = [DateTime]::Now
                $config = Join-Path $routerDir "config-$configMode.yaml"
                $routerProcess = Start-Process -FilePath $mihomo -ArgumentList ('-d "'+$routerDir+'" -f "'+$config+'"') -WindowStyle Hidden -PassThru
                $appliedMode = ''
                $lastRouteHealth = [DateTime]::MinValue
                Start-Sleep -Seconds 1
            }
            # A missing upstream/controller is a retryable state, never an exit.
            Ensure-LandingRuntime
            if ($appliedMode -and $appliedMode -ne $configMode) { Update-LandingRuntime }
            $appliedMode = $configMode
            $selectedChoice = Get-UpstreamChoice
            $expected = Get-UpstreamTarget $selectedChoice
            $active = (Invoke-LandingApi '/proxies/FIRST-HOP').now
            if ($active -ne $expected) { Set-LandingGroup 'FIRST-HOP' $expected }
            $landingChoice = Get-LandingChoice
            $target = Get-LandingTarget $landingChoice
            if ((Invoke-LandingApi '/proxies/LANDING').now -ne $target) { Set-LandingGroup 'LANDING' $target }

            if (([DateTime]::Now - $lastUpstreamHealth).TotalSeconds -ge 15) {
                $lastUpstreamHealth = [DateTime]::Now
                $endpoint = if (Test-Path $clashEndpointFile) { (Get-Content $clashEndpointFile -Raw).Trim() } else { '127.0.0.1:7980' }
                $port = if ($selectedChoice -eq 'wanda') { 7892 } else { [int]($endpoint.Split(':')[-1]) }
                $state = if (Test-LandingListener $port) { 'manual' } else { 'degraded' }
                Write-UpstreamHealth $state $expected '' -1 'local interface only; subscriptions and nodes owned by upstream'
            }
            if (([DateTime]::Now - $lastRouteHealth).TotalSeconds -ge 30) {
                $lastRouteHealth = [DateTime]::Now
                if ($landingChoice -eq 'nas04') { Ensure-Nas04Socks $SocksPort $TransportPort }
                if (Test-GermanExit) {
                    $routeFailures = 0
                    Write-Health 'healthy' "mode=$mode; exit=$script:lastGermanExit; observed_proxy=$($settings.Server)"
                } else {
                    $routeFailures++
                    Set-FailClosed 'Selected landing exit health check failed; waiting for the same upstream'
                    if ($landingChoice -eq 'nas04' -and $routeFailures -ge 2 -and
                        ([DateTime]::Now - $lastNasRecovery).TotalSeconds -ge 120) {
                        $lastNasRecovery = [DateTime]::Now
                        Write-Health 'recovering' 'NAS04 reconnecting same route'
                        Stop-Nas04Socks
                        Ensure-Nas04Socks $SocksPort $TransportPort
                    }
                }
            }
        } catch {
            Write-Health 'degraded' 'Selected route unavailable; supervisor will retry; upstream applications unchanged'
        } finally { $changeMutex.ReleaseMutex() }
        Start-Sleep -Seconds 2
    }
}
catch {
    Set-FailClosed "Supervisor exception: $($_.Exception.Message)"
}
finally {
    try {
        $finalMode = if (Test-Path -LiteralPath $modeFile) { (Get-Content -LiteralPath $modeFile -Raw).Trim().ToLowerInvariant() } else { 'off' }
        if ($finalMode -eq 'off') {
            if (Test-Path -LiteralPath $stopNas04Script) { & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $stopNas04Script -RouterDir $routerDir | Out-Null }
        } else { Write-Health 'degraded' 'Supervisor stopped; existing forwarding preserved; reconnect required' }
    }
    catch { Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) FALLBACK-BASE failed=$($_.Exception.Message)" }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    $changeMutex.Dispose()
}
