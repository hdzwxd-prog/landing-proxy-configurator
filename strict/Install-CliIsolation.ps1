$ErrorActionPreference='Stop'
$root=Join-Path $env:USERPROFILE '.ssh\GermanyRouter\StrictGermany'
$exe=Join-Path $env:APPDATA 'npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe'
$ff=Join-Path $env:LOCALAPPDATA 'Programs\Mozilla Firefox\firefox.exe'
$report=Join-Path $root 'cli-isolation.json'
try {
    & "$root\StrictNetworkLock.exe" ensure --app $exe 18485 --app $ff 18485
    if($LASTEXITCODE -ne 0){throw 'Additive isolation failed'}
    & "$root\StrictNetworkLock.exe" verify --app $exe 18485 --app $ff 18485
    if($LASTEXITCODE -ne 0){throw 'WFP verification failed'}
    @{ok=$true;exe=$exe;hash=(Get-FileHash $exe).Hash;verifiedAt=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content $report
} catch { @{ok=$false;error=$_.Exception.Message}|ConvertTo-Json|Set-Content $report;exit 1 }
