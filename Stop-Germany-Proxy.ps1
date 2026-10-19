$ErrorActionPreference = 'Continue'

$routerDir = 'C:\Users\250010031\.ssh\GermanyRouter'
$modeFile = Join-Path $routerDir 'mode.txt'
$previousMode = if (Test-Path $modeFile) { (Get-Content $modeFile -Raw).Trim().ToLowerInvariant() } else { 'off' }
$cleanupLog = Join-Path $routerDir 'cleanup.log'
$internetSettings = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$proxyBackupFile = Join-Path $routerDir 'proxy-restore.txt'

Set-Content -LiteralPath $modeFile -Value 'off' -Encoding ascii

Stop-ScheduledTask -TaskName 'Germany Rule Router 18484' -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskName 'Germany SOCKS Tunnel 18483' -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 700

# Stop only the processes created for this feature. Do not touch Clash Verge's
# own core or unrelated SSH sessions.
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
        ($_.Name -eq 'verge-mihomo.exe' -and $_.CommandLine -like '*\.ssh\GermanyRouter*') -or
        ($_.Name -eq 'ssh.exe' -and $_.CommandLine -like '*-D 127.0.0.1:18483*') -or
        ($_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*Start-Germany-Router.ps1*') -or
        ($_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*Start-Germany-Socks.ps1*')
    } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

if ($previousMode -eq 'apps') {
    $restoredTo = 'unchanged (apps-only mode)'
}
elseif (Test-Path -LiteralPath $proxyBackupFile) {
    $saved = @{}
    foreach ($line in Get-Content -LiteralPath $proxyBackupFile) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2) { $saved[$parts[0]] = $parts[1] }
    }
    $enabled = 0
    [int]::TryParse([string]$saved['ProxyEnable'], [ref]$enabled) | Out-Null
    New-ItemProperty -Path $internetSettings -Name ProxyEnable -PropertyType DWord -Value $enabled -Force | Out-Null
    New-ItemProperty -Path $internetSettings -Name ProxyServer -PropertyType String -Value ([string]$saved['ProxyServer']) -Force | Out-Null
    New-ItemProperty -Path $internetSettings -Name ProxyOverride -PropertyType String -Value ([string]$saved['ProxyOverride']) -Force | Out-Null
    $restoredTo = "saved proxy ($([string]$saved['ProxyServer']))"
    Remove-Item -LiteralPath $proxyBackupFile -Force -ErrorAction SilentlyContinue
}
else {
    $wandaListening = [bool](Get-NetTCPConnection -LocalAddress 127.0.0.1 -LocalPort 7892 -State Listen -ErrorAction SilentlyContinue)
    if ($wandaListening) {
        New-ItemProperty -Path $internetSettings -Name ProxyEnable -PropertyType DWord -Value 1 -Force | Out-Null
        New-ItemProperty -Path $internetSettings -Name ProxyServer -PropertyType String -Value '127.0.0.1:7892' -Force | Out-Null
        $restoredTo = '127.0.0.1:7892'
    }
    else {
        New-ItemProperty -Path $internetSettings -Name ProxyEnable -PropertyType DWord -Value 0 -Force | Out-Null
        $restoredTo = 'direct (ProxyEnable=0)'
    }
}
Add-Content -LiteralPath $cleanupLog -Value "$([DateTime]::Now.ToString('s')) stopped; restored=$restoredTo"
