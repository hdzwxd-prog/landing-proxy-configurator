param(
    [string]$RouterDir = (Join-Path $env:USERPROFILE '.ssh\GermanyRouter'),
    [int]$SocksPort = 18583,
    [int]$TransportPort = 18584
)
$ErrorActionPreference = 'Stop'
$healthFile = Join-Path $routerDir 'nas04-tunnel-health.txt'
$stateFile = Join-Path $routerDir 'nas04-process.json'
$logFile = Join-Path $routerDir 'nas04-ssh.log'
$sshPath = Join-Path $env:WINDIR 'System32\OpenSSH\ssh.exe'
$mutex = [Threading.Mutex]::new($false, "Local\GermanyNas04Socks$SocksPort")
if (-not $mutex.WaitOne(0)) { exit 0 }
$sshProcess = $null
function Save-State {
    $owner = Get-Process -Id $PID
    $state = @{ supervisor=$PID; supervisor_started=$owner.StartTime.ToUniversalTime().ToString('o'); ssh=0; ssh_started=''; socks_port=$SocksPort }
    if ($null -ne $script:sshProcess -and -not $script:sshProcess.HasExited) {
        $state.ssh=$script:sshProcess.Id
        $state.ssh_started=$script:sshProcess.StartTime.ToUniversalTime().ToString('o')
    }
    $state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8
}
function Stop-OwnedSsh {
    if ($null -ne $script:sshProcess -and -not $script:sshProcess.HasExited) {
        Stop-Process -Id $script:sshProcess.Id -Force -ErrorAction SilentlyContinue
        $script:sshProcess.WaitForExit(3000) | Out-Null
    }
}
try {
    New-Item -ItemType Directory -Path $routerDir -Force | Out-Null
    Save-State
    while ($true) {
        Set-Content -LiteralPath $healthFile -Encoding ascii -Value "$([DateTime]::Now.ToString('s'))|connecting"
        # Loopback transport is forwarded by our Mihomo through FIRST-HOP.
        # Never connect directly to the public NAS04 address as a fallback.
        if (-not (Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort $TransportPort -State Listen -ErrorAction SilentlyContinue)) {
            Start-Sleep -Seconds 3
            continue
        }
        if ((Test-Path $logFile) -and (Get-Item $logFile).Length -gt 1048576) { Set-Content $logFile '' }
        $sshArgs = @('-F','NUL','-N','-D',"127.0.0.1:$SocksPort",'-p',"$TransportPort",
            '-o','HostKeyAlias=212.121.132.230','-o','StrictHostKeyChecking=yes',
            '-o','BatchMode=yes','-o','ExitOnForwardFailure=yes','-o','ConnectTimeout=15',
            '-o','ConnectionAttempts=1','-o','ServerAliveInterval=10','-o','ServerAliveCountMax=2',
            '-o','TCPKeepAlive=yes','-o','IPQoS=none','-E',('"'+$logFile+'"'),'h50055690@127.0.0.1')
        $sshProcess = Start-Process -FilePath $sshPath -ArgumentList $sshArgs -WindowStyle Hidden -PassThru
        Save-State
        while (-not $sshProcess.WaitForExit(3000)) {
            Set-Content -LiteralPath $healthFile -Encoding ascii -Value "$([DateTime]::Now.ToString('s'))|running|via-first-hop"
        }
        Set-Content -LiteralPath $healthFile -Encoding ascii -Value "$([DateTime]::Now.ToString('s'))|disconnected"
        Start-Sleep -Seconds 3
    }
} finally {
    Stop-OwnedSsh
    $mutex.ReleaseMutex(); $mutex.Dispose()
}
