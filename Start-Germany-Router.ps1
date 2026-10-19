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
$refreshScript = Join-Path $routerDir 'Update-Germany-Upstreams.ps1'
$ensureClashScript = Join-Path $routerDir 'Ensure-Clash-Upstream.ps1'
$clashEndpointFile = Join-Path $routerDir 'clash-upstream.txt'
$desktopUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$internetSettingsSubKey = "$desktopUserSid\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
$mihomo = 'D:\Software\Clash Verge\verge-mihomo.exe'
$controller = 'http://127.0.0.1:19090'
$germanyExits = @('192.248.188.234','2a05:f480:1800:2d04:5400:5ff:fe92:1848')
$routerProcess = $null
$script:lastGermanExit = ''

function Write-Health([string]$state, [string]$detail) {
    Set-Content -LiteralPath $healthFile -Encoding utf8 -Value @(
        "timestamp=$([DateTime]::Now.ToString('s'))"
        "state=$state"
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

function Set-SystemProxy([string]$proxy) {
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

function Restart-EdgeNetworkService {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq 'msedge.exe' -and
            $_.CommandLine -like '*--utility-sub-type=network.mojom.NetworkService*'
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Restart-CodexNetworkService {
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq 'ChatGPT.exe' -and
            $_.CommandLine -like '*--utility-sub-type=network.mojom.NetworkService*'
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Set-FailClosed([string]$reason) {
    Set-SystemProxy '127.0.0.1:18484'
    Write-Health 'degraded' "$reason; fail_closed=127.0.0.1:18484"
    Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) FAIL-CLOSED $reason; kept=127.0.0.1:18484"
}

function Test-GermanExit {
    foreach ($url in @('https://api.ipify.org','https://ifconfig.me/ip')) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            [Net.ServicePointManager]::CheckCertificateRevocationList = $false
            $request = [Net.HttpWebRequest]::Create($url)
            $request.Proxy = New-Object Net.WebProxy('http://127.0.0.1:18484')
            $request.Timeout = 8000
            $request.ReadWriteTimeout = 8000
            $request.UserAgent = 'GermanyProxySupervisor/3.0'
            $response = $request.GetResponse()
            $reader = New-Object IO.StreamReader($response.GetResponseStream())
            $value = $reader.ReadToEnd().Trim()
            $reader.Dispose(); $response.Dispose()
            if ($germanyExits -contains $value) {
                $script:lastGermanExit = $value
                return $true
            }
            Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) health mismatch url=$url exit=$value"
        }
        catch {
            Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) health error url=$url error=$($_.Exception.Message)"
        }
    }
    return $false
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

function Test-BigAirportDelay {
    try {
        $group = [Uri]::EscapeDataString('BigAirport-SG')
        $testUrl = [Uri]::EscapeDataString('https://www.gstatic.com/generate_204')
        $result = Invoke-RestMethod -UseBasicParsing -Uri "$controller/proxies/$group/delay?url=$testUrl&timeout=7000" `
            -Headers (Get-ControllerHeaders) -TimeoutSec 9
        return [int]$result.delay
    }
    catch { return -1 }
}

function Get-ActiveUpstream {
    $state = Get-ProxyState 'FIRST-HOP'
    if ($state -and $state.now) { return [string]$state.now }
    return ''
}

function Get-BigAirportNode {
    $state = Get-ProxyState 'BigAirport-SG'
    if ($state -and $state.now) { return [string]$state.now }
    return ''
}

try {
    $mode = if (Test-Path $modeFile) { (Get-Content $modeFile -Raw).Trim().ToLowerInvariant() } else { 'off' }
    if ($mode -notin @('foreign','global')) { exit 0 }

    $upstreamChoice = if (Test-Path -LiteralPath $upstreamChoiceFile) {
        (Get-Content -LiteralPath $upstreamChoiceFile -Raw).Trim().ToLowerInvariant()
    } else { 'clash' }
    if ($upstreamChoice -notin @('clash','wanda','bigairport')) { $upstreamChoice='clash' }
    $clashEndpoint = if (Test-Path -LiteralPath $clashEndpointFile) { (Get-Content -LiteralPath $clashEndpointFile -Raw).Trim() } else { '127.0.0.1:7980' }
    if ($upstreamChoice -eq 'clash' -and (Test-Path -LiteralPath $ensureClashScript)) {
        & powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $ensureClashScript -Endpoint $clashEndpoint | Out-Null
    }

    $config = Join-Path $routerDir "config-$mode.yaml"
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
    else {
        $delay = Test-BigAirportDelay
        if ($delay -lt 0) { Set-FailClosed 'Legacy BigAirport group is unavailable'; exit 3 }
        Set-FirstHop 'BigAirport-SG' "legacy selection; delay=${delay}ms" | Out-Null
        Write-UpstreamHealth 'manual' 'BigAirport-SG' '' $delay 'legacy compatibility selection'
    }

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
        Set-SystemProxy '127.0.0.1:18484'
        Write-Health 'healthy' "mode=$mode; exit=$script:lastGermanExit"
        Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) active mode=$mode exit=$script:lastGermanExit"
        # Existing applications keep their sessions; the manager never restarts Codex or Edge.
    }

    $lastRouteHealth = [DateTime]::MinValue
    $lastUpstreamHealth = [DateTime]::MinValue
    while ($true) {
        Start-Sleep -Seconds 2
        $currentMode = if (Test-Path $modeFile) { (Get-Content $modeFile -Raw).Trim().ToLowerInvariant() } else { 'off' }
        if ($currentMode -notin @('foreign','global')) { break }
        if ($routerProcess.HasExited) { Set-FailClosed 'Router process exited unexpectedly'; break }

        $settings = Get-SystemProxyFresh
        if ($settings.Enabled -ne 1 -or $settings.Server -ne '127.0.0.1:18484') {
            Add-Content -LiteralPath $supervisorLog -Value "$([DateTime]::Now.ToString('s')) restoring active proxy from $($settings.Server) to 127.0.0.1:18484"
            Set-SystemProxy '127.0.0.1:18484'
        }

        if (([DateTime]::Now - $lastUpstreamHealth).TotalSeconds -ge 15) {
            $lastUpstreamHealth = [DateTime]::Now
            $selectedChoice = if (Test-Path -LiteralPath $upstreamChoiceFile) {
                (Get-Content -LiteralPath $upstreamChoiceFile -Raw).Trim().ToLowerInvariant()
            } else { 'clash' }
            $expected = if ($selectedChoice -eq 'clash') { 'Clash-Upstream' } elseif ($selectedChoice -eq 'wanda') { 'Wanda-Upstream' } else { 'BigAirport-SG' }
            $active = Get-ActiveUpstream
            if ($active -ne $expected) { Set-FirstHop $expected 'restore manual interface selection' | Out-Null; $active=$expected }
            $available = if ($active -eq 'Clash-Upstream') {
                [bool](Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $clashPort -State Listen -ErrorAction SilentlyContinue)
            } elseif ($active -eq 'Wanda-Upstream') {
                [bool](Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 7892 -State Listen -ErrorAction SilentlyContinue)
            } else { (Test-BigAirportDelay) -ge 0 }
            $state = if ($available) { 'manual' } else { 'degraded' }
            Write-UpstreamHealth $state $active '' -1 'manual Clash-compatible interface selection'
        }

        if (([DateTime]::Now - $lastRouteHealth).TotalSeconds -ge 30) {
            $lastRouteHealth = [DateTime]::Now
            if (Test-GermanExit) {
                Write-Health 'healthy' "mode=$currentMode; exit=$script:lastGermanExit; observed_proxy=$($settings.Server)"
            }
            else { Set-FailClosed 'Germany exit health check failed' }
        }
    }
}
catch {
    Set-FailClosed "Supervisor exception: $($_.Exception.Message)"
}
finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
