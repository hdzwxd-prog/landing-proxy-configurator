param([switch]$DryRun)

$ErrorActionPreference = 'Continue'

$routerDir = Join-Path $env:USERPROFILE '.ssh\GermanyRouter'
$modeFile = Join-Path $routerDir 'mode.txt'
$refreshScript = Join-Path $routerDir 'Update-Germany-Upstreams.ps1'

function Get-RouterProcesses {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.ProcessId -ne $PID -and $_.Name -eq 'verge-mihomo.exe' -and $_.CommandLine -like '*\.ssh\GermanyRouter*') -or
            ($_.ProcessId -ne $PID -and $_.Name -eq 'powershell.exe' -and
             $_.CommandLine -match '(?i)[\\\"'']Start-Germany-Router\.ps1(?:[\\\"'']|\s|$)')
        })
}

if ($DryRun) {
    $targets = Get-RouterProcesses
    [pscustomobject]@{
        self_pid=$PID
        self_selected=[bool]($targets.ProcessId -contains $PID)
        target_pids=@($targets.ProcessId)
        target_names=@($targets.Name)
    } | ConvertTo-Json -Compress
    exit 0
}

$mode = if (Test-Path -LiteralPath $modeFile) { (Get-Content -LiteralPath $modeFile -Raw).Trim().ToLowerInvariant() } else { 'off' }
if ($mode -notin @('foreign','global')) { exit 0 }

# Keep mode and WinINET proxy untouched. During this short restart, 18484 fails
# closed instead of exposing the first-hop or local address.
# Config is rebuilt by Ensure-Clash-Upstream.ps1 when the generic interface changes.
Stop-ScheduledTask -TaskName 'Germany Rule Router 18484' -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
Get-RouterProcesses |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500
Start-ScheduledTask -TaskName 'Germany Rule Router 18484'
