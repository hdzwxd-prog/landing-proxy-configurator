param([string]$RouterDir = (Join-Path $env:USERPROFILE '.ssh\GermanyRouter'))
$stateFile = Join-Path $routerDir 'nas04-process.json'
if (-not (Test-Path $stateFile)) { return }
try { $state = Get-Content $stateFile -Raw | ConvertFrom-Json } catch { return }
# Exact PID, executable name AND creation time prevent PID reuse from killing
# another SSH session. Stop the owner first so it cannot respawn its child.
foreach ($kind in @('supervisor','ssh')) {
    $id = [int]$state.$kind
    if ($id -le 0 -or $id -eq $PID) { continue }
    $process = Get-Process -Id $id -ErrorAction SilentlyContinue
    $expectedName = if ($kind -eq 'ssh') { 'ssh' } else { 'powershell' }
    $time = $state.($kind+'_started')
    if ($process -and $process.ProcessName -eq $expectedName -and $process.StartTime.ToUniversalTime().ToString('o') -eq $time) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit(3000) | Out-Null
    }
}
Set-Content -LiteralPath (Join-Path $routerDir 'nas04-tunnel-health.txt') -Encoding ascii -Value "$([DateTime]::Now.ToString('s'))|stopped"
