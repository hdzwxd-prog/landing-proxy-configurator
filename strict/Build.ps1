$ErrorActionPreference='Stop'
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if(-not $vs){throw 'Visual C++ Build Tools required'}
Push-Location $PSScriptRoot
try {
    $vcvars=Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
    $command='"'+$vcvars+'" >nul && cl /nologo /EHsc /W4 /O2 /DUNICODE /D_UNICODE StrictNetworkLock.cpp /Fe:StrictNetworkLock.exe /link /SUBSYSTEM:CONSOLE'
    & cmd.exe /d /s /c $command
    if($LASTEXITCODE -ne 0){throw 'Native build failed'}
} finally {Pop-Location}
