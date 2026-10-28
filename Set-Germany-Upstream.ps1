param(
    [Parameter(Mandatory=$true)][ValidateSet('clash','wanda')][string]$Choice,
    [string]$Endpoint = '127.0.0.1:7980',
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
if (-not (Enter-LandingChange $mutex 25000)) { $mutex.Dispose(); throw '另一个链路操作正在进行，请稍后重试。' }
$choiceFile = Join-Path $routerDir 'upstream-choice.txt'
$endpointFile = Join-Path $routerDir 'clash-upstream.txt'
$previous = Get-UpstreamChoice
$previousEndpoint = if (Test-Path $endpointFile) { (Get-Content $endpointFile -Raw).Trim() } else { '' }
$landing = Get-LandingChoice
$mode = (Get-Content (Join-Path $routerDir 'mode.txt') -Raw).Trim()
$changed = $false
$configChanged = $false
$savedFiles = @{}
try {
    # Preserve exact bytes for rollback, including the absence of a file.
    foreach ($name in @('config-foreign.yaml','config-global.yaml','clash-upstream.txt','upstream-choice.txt','upstream-health.txt')) {
        $path = Join-Path $routerDir $name
        $savedFiles[$path] = if (Test-Path $path) { [IO.File]::ReadAllBytes($path) } else { $null }
    }
    if ($Choice -eq 'clash' -and $Endpoint.Trim() -ne $previousEndpoint) {
        $configChanged = $true
        & (Join-Path $PSScriptRoot 'Ensure-Clash-Upstream.ps1') -Endpoint $Endpoint -RouterDir $routerDir -SocksPort $SocksPort -TransportPort $TransportPort -ProxyPort $ProxyPort -ControllerPort $ControllerPort | Out-Null
    }
    if ($mode -ne 'off') {
        if (-not (Test-LandingListener $ControllerPort)) { throw '落地服务未运行，请先点击重新连接。' }
        Write-LandingHealth $landing 'switching' "checking upstream=$Choice"
        $changed = $true
        if ($configChanged) { Update-LandingRuntime } else { Ensure-LandingRuntime }
        Set-LandingGroup 'FIRST-HOP' (Get-UpstreamTarget $Choice)
        if ($landing -eq 'nas04') { Stop-Nas04Socks; Ensure-Nas04Socks $SocksPort $TransportPort }
        if (-not (Test-LandingExit $landing $ProxyPort)) { throw '新上游未通过落地出口检测' }
    }
    Set-Content $choiceFile $Choice -Encoding ascii
    Set-Content (Join-Path $routerDir 'upstream-health.txt') -Encoding utf8 -Value @(
        "timestamp=$([DateTime]::Now.ToString('s'))",'state=manual',"active=$(Get-UpstreamTarget $Choice)"
    )
    if ($mode -eq 'off') { Write-LandingHealth $landing 'idle' 'upstream saved; service remains off' }
    else { Write-LandingHealth $landing 'healthy' "upstream=$Choice; exit=$script:verifiedExit" }
    Write-Output "choice=$Choice"
} catch {
    $failure = $_.Exception.Message
    $restored = $true
    try {
        foreach ($path in $savedFiles.Keys) {
            if ($null -eq $savedFiles[$path]) { if (Test-Path $path) { Remove-Item -LiteralPath $path } }
            else { [IO.File]::WriteAllBytes($path, [byte[]]$savedFiles[$path]) }
        }
        if ($changed) {
            if ($configChanged) { Update-LandingRuntime }
            Set-LandingGroup 'FIRST-HOP' (Get-UpstreamTarget $previous)
            if ($landing -eq 'nas04') { Stop-Nas04Socks; Ensure-Nas04Socks $SocksPort $TransportPort }
            $restored = Test-LandingExit $landing $ProxyPort
        }
    } catch { $restored = $false }
    if ($changed -and $restored) { Write-LandingHealth $landing 'healthy' "switch failed; previous upstream verified; exit=$script:verifiedExit" }
    else { Write-LandingHealth $landing 'pending' 'switch failed; original selection retained; recheck required' }
    if ($restored) { throw "$failure；已保留原上游选择。" }
    throw "$failure；原选择已保留，但链路未恢复，请重新连接。"
} finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
