param(
    [Parameter(Mandatory=$true)][ValidateSet('clash','wanda')][string]$Choice,
    [string]$Endpoint = '127.0.0.1:7980'
)
$ErrorActionPreference = 'Stop'
$routerDir = Join-Path $env:USERPROFILE '.ssh\GermanyRouter'
$controller = 'http://127.0.0.1:19090'
$runtimeScripts = Split-Path $routerDir -Parent
. (Join-Path $PSScriptRoot 'Landing.Common.ps1')
$mutex = [Threading.Mutex]::new($false, 'Local\LandingRouteChange19090')
if (-not (Enter-LandingChange $mutex 25000)) { throw '另一个链路操作正在进行，请稍后重试。' }
$choiceFile = Join-Path $routerDir 'upstream-choice.txt'
$endpointFile = Join-Path $routerDir 'clash-upstream.txt'
$previous = if (Test-Path $choiceFile) { (Get-Content $choiceFile -Raw).Trim() } else { 'clash' }
$previousEndpoint = if (Test-Path $endpointFile) { (Get-Content $endpointFile -Raw).Trim() } else { '127.0.0.1:7980' }
$landing = Get-LandingChoice
$running = [bool](Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 19090 -State Listen -ErrorAction SilentlyContinue)
$changed = $false
try {
    if ($Choice -eq 'clash') { & (Join-Path $PSScriptRoot 'Ensure-Clash-Upstream.ps1') -Endpoint $Endpoint | Out-Null }
    if ($running) {
        if ($Choice -eq 'clash') { Update-LandingRuntime } else { Ensure-LandingRuntime }
        Set-LandingGroup 'FIRST-HOP' (Get-UpstreamTarget $Choice)
        $changed = $true
        # Existing SSH sessions keep their original transport. Recreate only our
        # NAS04 tunnel when the user explicitly changes the first hop.
        if ($landing -eq 'nas04') { Stop-Nas04Socks; Ensure-Nas04Socks }
        if (-not (Test-LandingExit $landing)) { throw '新上游未通过落地出口检测' }
        Write-LandingHealth $landing 'healthy' "exit=$script:verifiedExit"
    }
    Set-Content $choiceFile $Choice -Encoding ascii
    Set-Content (Join-Path $routerDir 'upstream-health.txt') -Encoding utf8 -Value @(
        "timestamp=$([DateTime]::Now.ToString('s'))",'state=manual',"active=$(Get-UpstreamTarget $Choice)"
    )
    Write-Output "choice=$Choice"
} catch {
    $failure = $_.Exception.Message
    $restored = $true
    try {
        if ($Choice -eq 'clash') {
            & (Join-Path $PSScriptRoot 'Ensure-Clash-Upstream.ps1') -Endpoint $previousEndpoint | Out-Null
            if ($running) { Update-LandingRuntime }
        }
        if ($changed) {
            Set-LandingGroup 'FIRST-HOP' (Get-UpstreamTarget $previous)
            if ($landing -eq 'nas04') { Stop-Nas04Socks; Ensure-Nas04Socks }
        }
    } catch { $restored = $false }
    Write-LandingHealth $landing 'pending' 'upstream change failed; recheck required'
    if ($restored) { throw "$failure；已保留原上游选择。" }
    throw "$failure；恢复失败，请重新连接。"
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
