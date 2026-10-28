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

$winInetCode = @'
using System;
using System.Runtime.InteropServices;
public static class GermanyRouterWinInet {
    [DllImport("wininet.dll", SetLastError=true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int option, IntPtr buffer, int length);
}
'@
Add-Type $winInetCode -ErrorAction SilentlyContinue


$modeFile = Join-Path $routerDir 'mode.txt'
$healthFile = Join-Path $routerDir 'route-health.txt'
$upstreamHealthFile = Join-Path $routerDir 'upstream-health.txt'
$upstreamChoiceFile = Join-Path $routerDir 'upstream-choice.txt'
$supervisorLog = Join-Path $routerDir 'supervisor.log'
$controllerSecretFile = Join-Path $routerDir 'controller-secret.txt'
$stopNas04Script = Join-Path $routerDir '..\Stop-NAS04-Socks.ps1'
$clashEndpointFile = Join-Path $routerDir 'clash-upstream.txt'
$proxyBackupFile = Join-Path $routerDir 'proxy-restore.txt'
$desktopUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$internetSettingsSubKey = "$desktopUserSid\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
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

function Notify-ProxyChange {
    [GermanyRouterWinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
    [GermanyRouterWinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
}

function Save-BaseProxy {
    if (Test-Path -LiteralPath $proxyBackupFile) { return }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::Users, [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $base.OpenSubKey($internetSettingsSubKey, $false)
    try {
        Set-Content -LiteralPath $proxyBackupFile -Encoding utf8 -Value @(
            "ProxyEnable=$([int]$key.GetValue('ProxyEnable', 0))"
            "ProxyServer=$([string]$key.GetValue('ProxyServer', ''))"
            "ProxyOverride=$([string]$key.GetValue('ProxyOverride', ''))"
        )
    }
    finally { $key.Dispose(); $base.Dispose() }
}

function Set-SystemProxy([string]$proxy) {
    if ($Isolated) { throw 'Isolated supervisor cannot change system proxy.' }
    if ($mode -ne 'apps') { Save-BaseProxy }
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::Users, [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $base.OpenSubKey($internetSettingsSubKey, $true)
    $key.SetValue('ProxyEnable', 1, [Microsoft.Win32.RegistryValueKind]::DWord)
    $key.SetValue('ProxyServer', $proxy, [Microsoft.Win32.RegistryValueKind]::String)
    $proxyOverride = [string]$key.GetValue('ProxyOverride', '')
    $overrideItems = @($proxyOverride -split ';' | Where-Object { $_ })
    foreach ($schoolBypass in @('slai.edu.cn', '*.slai.edu.cn')) {
        if ($overrideItems -notcontains $schoolBypass) { $overrideItems += $schoolBypass }
    }
    $key.SetValue('ProxyOverride', ($overrideItems -join ';'), [Microsoft.Win32.RegistryValueKind]::String)
    $key.Dispose()
    $base.Dispose()
    Notify-ProxyChange
}

function Get-SystemProxyFresh {
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::Users, [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $base.OpenSubKey($internetSettingsSubKey, $false)
    try {
        return [pscustomobject]@{
            Enabled=[int]$key.GetValue('ProxyEnable', 0)
            Server=[string]$key.GetValue('ProxyServer', '')
        }
    }
    finally { $key.Dispose(); $base.Dispose() }
}

function Set-FailClosed([string]$reason) {
    if ($mode -ne 'apps') { Set-SystemProxy '127.0.0.1:18484' }
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
            $settings = Get-SystemProxyFresh
            # Only explicitly selected system-wide modes own the system proxy.
            if ($mode -ne 'apps' -and ($settings.Enabled -ne 1 -or $settings.Server -ne '127.0.0.1:18484')) {
                Set-SystemProxy '127.0.0.1:18484'
            }
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
