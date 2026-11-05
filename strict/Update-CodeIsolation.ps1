# Add missing version paths without deleting or replacing existing isolation.
param()
$ErrorActionPreference='Stop'
$root=Join-Path $env:USERPROFILE '.ssh\GermanyRouter\StrictGermany'
$report=Join-Path $root 'code-isolation-update.json'
try {
    $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if(-not $admin){throw 'Administrator permission required'}
    $statePath=Join-Path $root 'isolation-install.json'
    $state=Get-Content $statePath -Raw | ConvertFrom-Json
    if(-not $state.ok -or -not $state.claudeIncluded){throw 'Existing desktop isolation must be installed first'}
    $policy=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Claude'
    if($policy.egressProxyUrl -ne 'http://127.0.0.1:18485' -or $policy.egressProxyPacUrl){throw 'Claude managed proxy mismatch'}
    $package=Get-AppxPackage -Name Claude | Sort-Object Version -Descending | Select-Object -First 1
    if(-not $package){throw 'Claude package missing'}
    $codeDir=Join-Path $env:LOCALAPPDATA ('Claude-Data\'+$package.PackageFamilyName+'\claude-code')
    $code=@(Get-ChildItem -LiteralPath $codeDir -Filter 'claude.exe' -File -Recurse | Select-Object -ExpandProperty FullName | Sort-Object -Unique)
    if(-not $code.Count){throw 'No Claude Code engines found'}
    $native=Join-Path $root 'StrictNetworkLock.exe'
    $online=Join-Path $root 'isolation-check.exe'
    $offline=Join-Path $root 'isolation-check-offline.exe'
    foreach($path in @($online,$offline)){if(-not(Test-Path -LiteralPath $path)){throw 'Test probe missing'}}
    $addArgs=@('ensure')
    foreach($path in @($code)+@($online)){$addArgs+=@('--app',$path,'18485')}
    $addArgs+=@('--app',$offline,'18685')
    & $native @addArgs
    if($LASTEXITCODE -ne 0){throw 'Additive WFP transaction failed; old rules retained'}
    $targets=@(@($state.targets)+@($code)+@($online) | Where-Object {Test-Path -LiteralPath $_} | Sort-Object -Unique)
    $verifyArgs=@('verify')
    foreach($path in $targets){$verifyArgs+=@('--app',$path,'18485')}
    $verifyArgs+=@('--app',$offline,'18685')
    $verification=& $native @verifyArgs
    if($LASTEXITCODE -ne 0){throw 'Actual WFP predicate verification failed'}
    $filterStatus=& $native status
    if($LASTEXITCODE -ne 0){throw 'WFP status readback failed'}
    $stamp=Get-Date -Format yyyyMMddHHmmssfff
    Copy-Item -LiteralPath $statePath -Destination ($statePath+'.bak-'+$stamp)
    $state.targets=$targets
    $state.filterStatus=$filterStatus
    $state | Add-Member NoteProperty codeUpdatedAt ([DateTime]::UtcNow.ToString('o')) -Force
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
    @{ok=$true;updatedAt=[DateTime]::UtcNow.ToString('o');codeTargets=$code;verifiedTargetCount=$targets.Count+1;verification=$verification;filterStatus=$filterStatus;method='additive; previous rules retained';scope='exact Code executable paths, not arbitrary child executables'} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $report -Encoding UTF8
} catch {
    @{ok=$false;failedAt=[DateTime]::UtcNow.ToString('o');error=$_.Exception.Message} | ConvertTo-Json | Set-Content -LiteralPath $report -Encoding UTF8
    exit 1
}
