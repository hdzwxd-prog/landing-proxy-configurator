$ErrorActionPreference = 'Continue'
$mutex = [Threading.Mutex]::new($false, 'Local\GermanyRuleRouter18484')
if (-not $mutex.WaitOne(0)) { exit 0 }

$winInetCode = @'
using System;
using System.Runtime.InteropServices;
public static class GermanyRouterWinInet {
    [DllImport("wininet.dll", SetLastError=true)]
    public static extern bool InternetSetOption(IntPtr hInternet, int option, IntPtr buffer, int length);
}
'@
Add-Type $winInetCode -ErrorAction SilentlyContinue

$routerDir = Join-Path $env:USERPROFILE '.ssh\GermanyRouter'
$modeFile = Join-Path $routerDir 'mode.txt'
$healthFile = Join-Path $routerDir 'route-health.txt'
$upstreamHealthFile = Join-Path $routerDir 'upstream-health.txt'
$upstreamChoiceFile = Join-Path $routerDir 'upstream-choice.txt'
$supervisorLog = Join-Path $routerDir 'supervisor.log'
$controllerSecretFile = Join-Path $routerDir 'controller-secret.txt'
$ensureClashScript = Join-Path $routerDir 'Ensure-Clash-Upstream.ps1'
$startNas04Script = Join-Path $routerDir '..\Start-NAS04-Socks.ps1'
$stopNas04Script = Join-Path $routerDir '..\Stop-NAS04-Socks.ps1'
$clashEndpointFile = Join-Path $routerDir 'clash-upstream.txt'
$proxyBackupFile = Join-Path $routerDir 'proxy-restore.txt'
$desktopUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$internetSettingsSubKey = "$desktopUserSid\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$mihomo = Join-Path $routerDir 'landing-router-core.exe'
if (-not (Test-Path $mihomo)) { Copy-Item -LiteralPath 'D:\Software\Clash Verge\verge-mihomo.exe' -Destination $mihomo -ErrorAction Stop }
$controller = 'http://127.0.0.1:19090'
$runtimeScripts = $PSScriptRoot
. (Join-Path $routerDir 'Landing.Common.ps1')
$changeMutex = [Threading.Mutex]::new($false, 'Local\LandingRouteChange19090')
$routerProcess = $null
$script:lastGermanExit = ''

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

function Restore-BaseProxy([string]$reason) {
    if (-not (Test-Path -LiteralPath $proxyBackupFile)) { return }
    $saved = @{}
    foreach ($line in Get-Content -LiteralPath $proxyBackupFile) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) { $saved[$parts[0]] = $parts[1] }
    }
    $enabled = 0
    [int]::TryParse([string]$saved['ProxyEnable'], [ref]$enabled) | Out-Null
    $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
        [Microsoft.Win32.RegistryHive]::Users, [Microsoft.Win32.RegistryView]::Registry64
    )
    $key = $base.OpenSubKey($internetSettingsSubKey, $true)
    try {
        $key.SetValue('ProxyEnable', $enabled, [Microsoft.Win32.RegistryValueKind]::DWord)
        $key.SetValue('ProxyServer', [string]$saved['ProxyServer'], [Microsoft.Win32.RegistryValueKind]::String)
        $key.SetValue('ProxyOverride', [string]$saved['ProxyOverride'], [Microsoft.Win32.RegistryValueKind]::String)
    }
    finally { $key.Dispose(); $base.Dispose() }
    Notify-ProxyChange
    Remove-Item -LiteralPath $proxyBackupFile -Force -ErrorAction SilentlyContinue
    Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) FALLBACK-BASE reason=$reason restored=$([string]$saved['ProxyServer'])"
}

function Set-SystemProxy([string]$proxy) {
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
    $ok = Test-LandingExit (Get-LandingChoice)
    if ($ok) { $script:lastGermanExit = $script:verifiedExit }
    return $ok
}

function Get-ControllerHeaders {
    if (-not (Test-Path -LiteralPath $controllerSecretFile)) { return @{} }
    $secret = (Get-Content -LiteralPath $controllerSecretFile -Raw).Trim()
    return @{ Authorization="Bearer $secret" }
}

function Get-ProxyState([string]$name) {
    try {
        $encoded = [Uri]::EscapeDataString($name)
        return Invoke-RestMethod -UseBasicParsing -Uri "$controller/proxies/$encoded" -Headers (Get-ControllerHeaders) -TimeoutSec 4
    }
    catch { return $null }
}

function Set-FirstHop([string]$name, [string]$reason) {
    try {
        $encoded = [Uri]::EscapeDataString('FIRST-HOP')
        $body = @{ name=$name } | ConvertTo-Json -Compress
        Invoke-RestMethod -UseBasicParsing -Method Put -Uri "$controller/proxies/$encoded" `
            -Headers (Get-ControllerHeaders) -ContentType 'application/json' -Body $body -TimeoutSec 4 | Out-Null
        Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) first-hop=$name reason=$reason"
        return $true
    }
    catch {
        Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) first-hop switch failed target=$name error=$($_.Exception.Message)"
        return $false
    }
}

function Get-ActiveUpstream {
    $state = Get-ProxyState 'FIRST-HOP'
    if ($state -and $state.now) { return [string]$state.now }
    return ''
}


try {
    $mode = if (Test-Path $modeFile) { (Get-Content $modeFile -Raw).Trim().ToLowerInvariant() } else { 'off' }
    if ($mode -notin @('foreign','global','apps')) { exit 0 }

    $upstreamChoice = if (Test-Path -LiteralPath $upstreamChoiceFile) {
        (Get-Content -LiteralPath $upstreamChoiceFile -Raw).Trim().ToLowerInvariant()
    } else { 'clash' }
    if ($upstreamChoice -notin @('clash','wanda')) { $upstreamChoice='clash' }
    $clashEndpoint = if (Test-Path -LiteralPath $clashEndpointFile) { (Get-Content -LiteralPath $clashEndpointFile -Raw).Trim() } else { '127.0.0.1:7980' }
    if ($upstreamChoice -eq 'clash' -and (Test-Path -LiteralPath $ensureClashScript)) {
        & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $ensureClashScript -Endpoint $clashEndpoint | Out-Null
    }

    $configMode = Get-LandingConfigMode $mode
    $config = Join-Path $routerDir "config-$configMode.yaml"
    Write-Health 'starting' "mode=$mode"
    Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) starting mode=$mode"
    $existing = Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 18484 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) {
        $routerProcess = Get-Process -Id $existing.OwningProcess -ErrorAction Stop
        Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) reusing router pid=$($routerProcess.Id)"
    }
    else {
        $routerProcess = Start-Process -FilePath $mihomo -ArgumentList @('-d',$routerDir,'-f',$config) -WindowStyle Hidden -PassThru
    }

    $controllerReady = $false
    for ($i=0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 500
        if ($routerProcess.HasExited) { break }
        if (Get-ProxyState 'FIRST-HOP') { $controllerReady=$true; break }
    }
    if (-not $controllerReady) {
        Set-FailClosed 'Router controller did not become ready'
        exit 3
    }

    $clashPort = 7980
    if ($clashEndpoint -match ':(\d+)$') { $clashPort = [int]$Matches[1] }
    $clashAvailable = [bool](Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $clashPort -State Listen -ErrorAction SilentlyContinue)
    $wandaAvailable = [bool](Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 7892 -State Listen -ErrorAction SilentlyContinue)
    if ($upstreamChoice -eq 'clash') {
        if (-not $clashAvailable) { Set-FailClosed "Selected Clash interface is not listening on $clashEndpoint"; exit 3 }
        Set-FirstHop 'Clash-Upstream' 'manual Clash-compatible interface selection' | Out-Null
        Write-UpstreamHealth 'manual' 'Clash-Upstream' '' -1 "manual interface $clashEndpoint"
    }
    elseif ($upstreamChoice -eq 'wanda') {
        if (-not $wandaAvailable) { Set-FailClosed 'Selected WandaCloud compatibility interface is not listening on 7892'; exit 3 }
        Set-FirstHop 'Wanda-Upstream' 'manual compatibility interface selection' | Out-Null
        Write-UpstreamHealth 'manual' 'Wanda-Upstream' '' -1 'manual compatibility interface selection'
    }

    Ensure-LandingRuntime
    $landingChoice = Get-LandingChoice
    if ($landingChoice -eq 'nas04') { Ensure-Nas04Socks }
    Set-LandingGroup 'LANDING' (Get-LandingTarget $landingChoice)

    $ready = $false
    for ($i=0; $i -lt 4; $i++) {
        Start-Sleep -Seconds 2
        if ($routerProcess.HasExited) { break }
        if (Test-GermanExit) { $ready=$true; break }
    }
    if (-not $ready) {
        Set-FailClosed 'Germany route did not become healthy during startup'
        if ($routerProcess.HasExited) { exit 3 }
    }
    else {
        if ($mode -ne 'apps') { Set-SystemProxy '127.0.0.1:18484' }
        Write-Health 'healthy' "mode=$mode; exit=$script:lastGermanExit"
        Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) active mode=$mode exit=$script:lastGermanExit"
        # Existing applications keep their sessions; the manager never restarts Codex or Edge.
    }

    $lastRouteHealth = [DateTime]::MinValue
    $lastUpstreamHealth = [DateTime]::MinValue
    while ($true) {
        Start-Sleep -Seconds 2
        $currentMode = if (Test-Path $modeFile) { (Get-Content $modeFile -Raw).Trim().ToLowerInvariant() } else { 'off' }
        if ($currentMode -notin @('foreign','global','apps')) { break }
        if ($routerProcess.HasExited) { Set-FailClosed 'Router process exited unexpectedly'; break }

        $settings = Get-SystemProxyFresh
        if ($currentMode -ne 'apps' -and ($settings.Enabled -ne 1 -or $settings.Server -ne '127.0.0.1:18484')) {
            Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) restoring active proxy from $($settings.Server) to 127.0.0.1:18484"
            Set-SystemProxy '127.0.0.1:18484'
        }

        if (-not (Enter-LandingChange $changeMutex)) { continue }
        try {
        if (([DateTime]::Now - $lastUpstreamHealth).TotalSeconds -ge 15) {
            $lastUpstreamHealth = [DateTime]::Now
            $selectedChoice = if (Test-Path -LiteralPath $upstreamChoiceFile) {
                (Get-Content -LiteralPath $upstreamChoiceFile -Raw).Trim().ToLowerInvariant()
            } else { 'clash' }
            $expected = Get-UpstreamTarget $selectedChoice
            $active = Get-ActiveUpstream
            if ($active -ne $expected) { Set-FirstHop $expected 'restore manual interface selection' | Out-Null; $active=$expected }
            $available = if ($active -eq 'Clash-Upstream') {
                [bool](Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $clashPort -State Listen -ErrorAction SilentlyContinue)
            } elseif ($active -eq 'Wanda-Upstream') {
                [bool](Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 7892 -State Listen -ErrorAction SilentlyContinue)
            } else { $false }
            $state = if ($available) { 'manual' } else { 'degraded' }
            Write-UpstreamHealth $state $active '' -1 'manual Clash-compatible interface selection'
        }

        if (([DateTime]::Now - $lastRouteHealth).TotalSeconds -ge 30) {
            $lastRouteHealth = [DateTime]::Now
            if (Test-GermanExit) {
                Write-Health 'healthy' "mode=$currentMode; exit=$script:lastGermanExit; observed_proxy=$($settings.Server)"
            }
            else { Set-FailClosed 'Selected landing exit health check failed' }
        }
        } finally { $changeMutex.ReleaseMutex() }
    }
}
catch {
    Set-FailClosed "Supervisor exception: $($_.Exception.Message)"
}
finally {
    if (Test-Path -LiteralPath $stopNas04Script) {
        & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $stopNas04Script | Out-Null
    }
    try {
        $finalMode = if (Test-Path -LiteralPath $modeFile) { (Get-Content -LiteralPath $modeFile -Raw).Trim().ToLowerInvariant() } else { 'off' }
        if ($finalMode -ne 'apps') { Restore-BaseProxy 'landing supervisor exited' }
    }
    catch { Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) FALLBACK-BASE failed=$($_.Exception.Message)" }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    $changeMutex.Dispose()
}
