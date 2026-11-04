param([switch]$IncludeClaude)
$ErrorActionPreference='Stop'
$root=Join-Path $env:USERPROFILE '.ssh\GermanyRouter\StrictGermany'
$report=Join-Path $root 'isolation-install.json'
try {
    $isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if(-not $isAdmin){throw 'Administrator elevation is required for persistent application network filters.'}
    if(Test-Path $report){
        $prior=Get-Content $report -Raw | ConvertFrom-Json
        if($prior.ok -and $prior.claudeIncluded){$IncludeClaude=$true}
    }
    $ff=Join-Path $env:LOCALAPPDATA 'Programs\Mozilla Firefox'
    $targets=@(Get-ChildItem -LiteralPath $ff -Filter '*.exe' -File | Select-Object -ExpandProperty FullName)
    $targets+=Join-Path $root 'isolation-probe.exe'
    $arguments=@('install')
    foreach($path in $targets){$arguments+=@('--app',$path,'18485')}
    # The independent core itself may only reach the selected first-hop socket.
    $config=Get-Content (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
    $upstream=@($config.proxies | Where-Object name -eq 'STRICT-UPSTREAM')[0]
    if($upstream.server -ne '127.0.0.1'){throw 'Non-local first hop refused'}
    $arguments+=@('--core',(Join-Path $root 'strict-germany-core.exe'),'0')
    if($IncludeClaude){
        $key='HKLM:\SOFTWARE\Policies\Claude'
        $existing=Get-ItemProperty $key -ErrorAction SilentlyContinue
        if($existing -and $existing.egressProxyPacUrl){throw 'Existing Claude PAC conflicts with strict proxy; review required'}
        if(Test-Path $key){
            & reg.exe export 'HKLM\SOFTWARE\Policies\Claude' (Join-Path $root ('claude-policy-backup-'+(Get-Date -Format yyyyMMddHHmmss)+'.reg')) /y | Out-Null
            if($LASTEXITCODE -ne 0){throw 'Claude policy backup failed'}
        }
        $package=Get-AppxPackage -Name Claude | Sort-Object Version -Descending | Select-Object -First 1
        if(-not $package){throw 'Claude package missing'}
        $claudePaths=@(Get-ChildItem -LiteralPath (Join-Path $package.InstallLocation 'app') -Filter '*.exe' -File -Recurse | Select-Object -ExpandProperty FullName)
        $codeDir=Join-Path $env:LOCALAPPDATA ('Claude-Data\'+$package.PackageFamilyName+'\claude-code')
        if(Test-Path $codeDir){$claudePaths+=@(Get-ChildItem -LiteralPath $codeDir -Filter 'claude.exe' -File -Recurse | Select-Object -ExpandProperty FullName)}
        foreach($path in $claudePaths){$arguments+=@('--app',$path,'18485')}
        $arguments+=@('--package',$package.PackageFamilyName,'18485')
        $targets+=$claudePaths
    }
    & (Join-Path $root 'StrictNetworkLock.exe') @arguments
    if($LASTEXITCODE -ne 0){throw 'WFP transaction failed; previous filters retained'}
    if($IncludeClaude){
        New-Item $key -Force | Out-Null
        New-ItemProperty $key -Name egressProxyUrl -Value 'http://127.0.0.1:18485' -PropertyType String -Force | Out-Null
    }
    $filterStatus=& (Join-Path $root 'StrictNetworkLock.exe') status
    if($LASTEXITCODE -ne 0){throw 'Unable to read back active WFP filters'}
    $state=@{ok=$true;installedAt=[DateTime]::UtcNow.ToString('o');claudeIncluded=[bool]$IncludeClaude;targets=$targets;port=18485;upstreamPort=$upstream.port;filterStatus=$filterStatus}
    $state | ConvertTo-Json -Depth 5 | Set-Content $report -Encoding UTF8
} catch {
    @{ok=$false;error=$_.Exception.Message;failedAt=[DateTime]::UtcNow.ToString('o')} | ConvertTo-Json | Set-Content (Join-Path $root 'isolation-install-error.json') -Encoding UTF8
    exit 1
}
