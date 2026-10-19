$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\Landing.Common.ps1')
foreach($mode in @('apps','global','foreign')) {
    $expected=if($mode -eq 'foreign'){'foreign'}else{'global'}
    if((Get-LandingConfigMode $mode) -ne $expected){throw "Wrong routing for $mode"}
}
# Verify reload uses the same selector as startup, without touching a live core.
$routerDir=Join-Path $env:TEMP ('landing-routing-test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($routerDir)|Out-Null
function Invoke-LandingApi($path,$method,$body) {
    if($path -eq '/proxies/FIRST-HOP'){return @{now='Clash-Upstream'}}
    if($path -eq '/configs?force=true'){$script:loadedPath=$body.path}
}
function Set-LandingGroup($group,$target) {}
try {
    foreach($mode in @('apps','global','foreign')) {
        [IO.File]::WriteAllText((Join-Path $routerDir 'mode.txt'),$mode)
        Update-LandingRuntime
        $expected=Join-Path $routerDir ('config-'+(Get-LandingConfigMode $mode)+'.yaml')
        if($script:loadedPath -ne $expected){throw "Wrong reload config for $mode"}
    }
    'PASS: app/global public traffic uses landing rules; foreign mode retains separate routing'
}finally {
    Remove-Item -LiteralPath (Join-Path $routerDir 'mode.txt')
    [IO.Directory]::Delete($routerDir)
}
