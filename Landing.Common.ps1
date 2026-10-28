# Shared by the UI commands and supervisor. These APIs belong to our independent
# router only; never call or configure the user's Clash/Wanda controller.
function Get-LandingChoice {
    $file = Join-Path $routerDir 'landing-choice.txt'
    if ((Test-Path $file) -and (Get-Content $file -Raw).Trim() -eq 'nas04') { return 'nas04' }
    return 'germany'
}

function Get-LandingTarget([string]$choice) {
    if ($choice -eq 'nas04') { return 'NAS04-SSH' }
    return 'Germany-VLESS'
}

function Get-UpstreamTarget([string]$choice) {
    switch ($choice) {
        'wanda' { return 'Wanda-Upstream' }
        default { return 'Clash-Upstream' }
    }
}

function Get-LandingExits([string]$choice) {
    if ($choice -eq 'nas04') { return @('212.121.132.230') }
    return @('192.248.188.234','2a05:f480:1800:2d04:5400:5ff:fe92:1848')
}

function Invoke-LandingApi([string]$path, [string]$method = 'GET', $body = $null) {
    $request = [Net.HttpWebRequest]::Create($controller + $path)
    $request.Proxy = $null
    $request.Method = $method
    $request.Timeout = 10000
    $request.ReadWriteTimeout = 10000
    $request.Headers['Authorization'] = 'Bearer ' + (Get-Content (Join-Path $routerDir 'controller-secret.txt') -Raw).Trim()
    if ($null -ne $body) {
        $bytes = [Text.Encoding]::UTF8.GetBytes(($body | ConvertTo-Json -Compress))
        $request.ContentType = 'application/json'
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    }
    $response = $request.GetResponse()
    try {
        $reader = New-Object IO.StreamReader($response.GetResponseStream())
        try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $response.Dispose() }
    if ($text) { return ($text | ConvertFrom-Json) }
}

function Set-LandingGroup([string]$group, [string]$target) {
    Invoke-LandingApi ('/proxies/' + [Uri]::EscapeDataString($group)) 'PUT' @{name=$target} | Out-Null
}

function Test-LandingExit([string]$choice, [int]$proxyPort = 18484) {
    $script:verifiedExit = ''
    foreach ($url in @('https://api.ipify.org','https://ifconfig.me/ip')) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $request = [Net.HttpWebRequest]::Create($url)
            # A route change must be verified with a NEW transport, never a
            # keep-alive connection established through the previous first hop.
            $request.KeepAlive = $false
            $request.ConnectionGroupName = [Guid]::NewGuid().ToString('N')
            $request.Proxy = New-Object Net.WebProxy("http://127.0.0.1:$proxyPort")
            $request.Timeout = 8000
            $request.ReadWriteTimeout = 8000
            $response = $request.GetResponse()
            try {
                $reader = New-Object IO.StreamReader($response.GetResponseStream())
                try { $ip = $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
            } finally { $response.Dispose() }
            if ($ip -in (Get-LandingExits $choice)) { $script:verifiedExit = $ip; return $true }
        } catch { }
    }
    return $false
}

function Write-LandingHealth([string]$choice, [string]$state, [string]$detail) {
    Set-Content -LiteralPath (Join-Path $routerDir 'route-health.txt') -Encoding utf8 -Value @(
        "timestamp=$([DateTime]::Now.ToString('s'))", "state=$state", "landing=$choice", "detail=$detail"
    )
}

function Get-LandingConfigMode([ValidateSet('foreign','global','apps')][string]$mode) {
    # App-scoped traffic must not inherit the China-direct rules. Scope comes
    # from each app's explicit proxy, not from relaxing public-site routing.
    if ($mode -eq 'foreign') { return 'foreign' }
    return 'global'
}

function Update-LandingRuntime {
    $first = (Invoke-LandingApi '/proxies/FIRST-HOP').now
    $landing = Get-LandingChoice
    $mode = (Get-Content (Join-Path $routerDir 'mode.txt') -Raw).Trim()
    $configMode = Get-LandingConfigMode $mode
    Invoke-LandingApi '/configs?force=true' 'PUT' @{path=(Join-Path $routerDir "config-$configMode.yaml")} | Out-Null
    Set-LandingGroup 'FIRST-HOP' $first
    Set-LandingGroup 'LANDING' (Get-LandingTarget $landing)
}

function Ensure-LandingRuntime {
    $state = $null
    try { $state = Invoke-LandingApi '/proxies/LANDING' } catch { }
    if (-not $state -or $state.all -notcontains 'NAS04-SSH') { Update-LandingRuntime }
}

function Ensure-Nas04Socks([int]$socksPort = 18583, [int]$transportPort = 18584) {
    if (Test-LandingListener $socksPort) { return }
    $scriptFile = Join-Path $runtimeScripts 'Start-NAS04-Socks.ps1'
    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptFile + '" -RouterDir "' + $routerDir + '" -SocksPort ' + $socksPort + ' -TransportPort ' + $transportPort
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList $arguments | Out-Null
    for ($i=0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 500
        if (Test-LandingListener $socksPort) { return }
    }
    throw 'NAS04 SSH 未就绪，请确认所选上游可用及 SSH 密钥登录正常。'
}

function Stop-Nas04Socks {
    & (Join-Path $runtimeScripts 'Stop-NAS04-Socks.ps1') -RouterDir $routerDir
}

function Enter-LandingChange($mutex, [int]$timeout = 0) {
    try { return $mutex.WaitOne($timeout) }
    catch [Threading.AbandonedMutexException] { return $true }
}

function Test-LandingListener([int]$port) {
    return [bool]([Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() | Where-Object { $_.Port -eq $port -and $_.Address.ToString() -eq '127.0.0.1' })
}

function Get-UpstreamChoice {
    $file = Join-Path $routerDir 'upstream-choice.txt'
    if ((Test-Path $file) -and (Get-Content $file -Raw).Trim() -eq 'wanda') { return 'wanda' }
    return 'clash'
}

function Invoke-LandingReconnect([int]$proxyPort = 18484, [int]$socksPort = 18583, [int]$transportPort = 18584, [bool]$reload = $false) {
    $landing = Get-LandingChoice
    Write-LandingHealth $landing 'recovering' 'reconnecting selected route; upstream applications unchanged'
    try {
        if ($reload) { Update-LandingRuntime } else { Ensure-LandingRuntime }
        Set-LandingGroup 'FIRST-HOP' (Get-UpstreamTarget (Get-UpstreamChoice))
        Set-LandingGroup 'LANDING' (Get-LandingTarget $landing)
        if ($landing -eq 'nas04') { Stop-Nas04Socks; Ensure-Nas04Socks $socksPort $transportPort }
        if (-not (Test-LandingExit $landing $proxyPort)) { throw '所选链路出口检测失败；请检查上游客户端及节点，选择保持不变。' }
        Write-LandingHealth $landing 'healthy' "reconnected; exit=$script:verifiedExit"
    } catch {
        Write-LandingHealth $landing 'degraded' 'reconnect failed; selected route retained; no direct fallback'
        throw
    }
}
