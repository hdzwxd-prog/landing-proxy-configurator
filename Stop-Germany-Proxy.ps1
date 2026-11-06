$ErrorActionPreference = 'Stop'

$routerDir = Join-Path $env:USERPROFILE '.ssh\GermanyRouter'
$modeFile = Join-Path $routerDir 'mode.txt'
$cleanupLog = Join-Path $routerDir 'cleanup.log'

Set-Content -LiteralPath $modeFile -Value 'off' -Encoding ascii

Stop-ScheduledTask -TaskName 'Germany Rule Router 18484' -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskName 'Germany SOCKS Tunnel 18483' -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 700

# Stop only the processes created for this feature. Do not touch Clash Verge's
# own core or unrelated SSH sessions.
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ProcessId -ne $PID -and (
        ($_.Name -in @('verge-mihomo.exe','landing-router-core.exe') -and $_.CommandLine -like '*\.ssh\GermanyRouter*') -or
        ($_.Name -eq 'ssh.exe' -and $_.CommandLine -like '*-D 127.0.0.1:18483*') -or
        ($_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*Start-Germany-Router.ps1*') -or
        ($_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*Start-Germany-Socks.ps1*'))
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

& (Join-Path $PSScriptRoot 'Stop-NAS04-Socks.ps1')

# Ownership boundary: stopping this service never restores a stale OS proxy snapshot.
# System settings belong to Windows and the upstream client chosen by the user.
$remaining=@(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { $_.LocalPort -in @(18484,18583,18584) })
if($remaining.Count){throw '落地端口仍在监听；未能确认停止成功。'}
Add-Content -LiteralPath $cleanupLog -Value "$([DateTime]::Now.ToString('s')) stopped; system_proxy=untouched"
