$ErrorActionPreference='Stop'
$root=Join-Path $env:TEMP ('landing-stop-test-'+[guid]::NewGuid().ToString('N'))
$oldProfile=$env:USERPROFILE
New-Item -ItemType Directory -Path (Join-Path $root '.ssh\GermanyRouter') -Force|Out-Null
try {
    $env:USERPROFILE=$root
    Copy-Item (Join-Path $PSScriptRoot '..\Stop-Germany-Proxy.ps1') (Join-Path $root '.ssh\Stop-Germany-Proxy.ps1')
    Set-Content (Join-Path $root '.ssh\Stop-NAS04-Socks.ps1') '# offline stub'
    Set-Content (Join-Path $root '.ssh\GermanyRouter\mode.txt') 'global'
    Set-Content (Join-Path $root '.ssh\GermanyRouter\proxy-restore.txt') 'ProxyServer=old-user-choice'
    function Stop-ScheduledTask {}
    function Get-CimInstance {return @()}
    function Stop-Process {throw 'Unexpected real process stop'}
    function New-ItemProperty {throw 'System registry mutation is forbidden'}
    function Set-ItemProperty {throw 'System registry mutation is forbidden'}
    function Get-NetTCPConnection {if(Test-Path (Join-Path $env:USERPROFILE 'simulate-listener')){[pscustomobject]@{LocalPort=18484}}}
    & (Join-Path $root '.ssh\Stop-Germany-Proxy.ps1')
    if(-not (Test-Path (Join-Path $root '.ssh\GermanyRouter\proxy-restore.txt'))){throw 'Consumed an old user proxy snapshot'}
    Set-Content (Join-Path $root 'simulate-listener') 'true'
    $rejected=$false
    try{& (Join-Path $root '.ssh\Stop-Germany-Proxy.ps1')}catch{$rejected=$true}
    if(-not $rejected){throw 'Surviving service must not be reported as successfully stopped'}
    'PASS: stop preserves system ownership and fails when a listener survives'
} finally {
    $env:USERPROFILE=$oldProfile
    $resolved=[IO.Path]::GetFullPath($root)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath($env:TEMP).TrimEnd('\')+'\landing-stop-test-')){throw 'Unexpected test directory'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
