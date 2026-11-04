param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$root=Join-Path $env:USERPROFILE '.ssh\GermanyRouter\StrictGermany'
$exe=Join-Path $root 'strict-germany-core.exe'
$listener=Get-NetTCPConnection -State Listen -LocalPort 18485 -ErrorAction SilentlyContinue
if($listener) {
    $owner=Get-Process -Id $listener[0].OwningProcess -ErrorAction Stop
    if($owner.Path -ne $exe){throw '18485 is owned by another program; refused.'}
} elseif(-not $CheckOnly) {
    foreach($name in @('core.out.log','core.err.log')) {
        $log=Join-Path $root $name
        if((Test-Path $log) -and (Get-Item $log).Length -gt 2MB){Move-Item $log ($log+'.previous') -Force}
    }
    Start-Process -FilePath $exe -ArgumentList ('-d "'+$root+'" -f "'+(Join-Path $root 'config.json')+'"') -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'core.out.log') -RedirectStandardError (Join-Path $root 'core.err.log') | Out-Null
    Start-Sleep -Milliseconds 700
}
$verified=$false
foreach($url in @('https://api.ipify.org','https://ipinfo.io/ip')) {
    $result=& curl.exe --silent --fail --proxy http://127.0.0.1:18485 --connect-timeout 8 --max-time 12 $url
    if($LASTEXITCODE -eq 0 -and "$result".Trim() -in @('192.248.188.234','2a05:f480:1800:2d04:5400:5ff:fe92:1848')){$verified=$true;break}
}
if(-not $verified){throw 'Germany-only exit check failed. No alternative route was selected.'}
Write-Output ('Strict Germany verified: '+$result)
