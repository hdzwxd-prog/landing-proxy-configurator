$ErrorActionPreference='Stop'
$root=Join-Path $env:USERPROFILE '.ssh\GermanyRouter\StrictGermany'
$stable=Join-Path $env:LOCALAPPDATA 'LandingProxyConfigurator\bin'
$npm=Join-Path $env:APPDATA 'npm'
$archive=Join-Path $env:LOCALAPPDATA ('LandingProxyConfigurator\Archive\cli-'+(Get-Date -Format yyyyMMddHHmmssfff))
New-Item -ItemType Directory -Force $stable,$archive|Out-Null
foreach($file in 'Invoke-ProtectedClaude.ps1','Test-LoginPrerequisites.ps1') { Copy-Item (Join-Path $PSScriptRoot $file) $root -Force }
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe /r:System.Web.dll /r:System.Web.Extensions.dll /r:System.Windows.Forms.dll ("/out:"+(Join-Path $root 'ProtectedAuthBrowser.exe')) (Join-Path $PSScriptRoot 'ProtectedAuthBrowser.cs')
if($LASTEXITCODE -ne 0){throw 'Browser dispatcher build failed'}
$ps='& powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\.ssh\GermanyRouter\StrictGermany\Invoke-ProtectedClaude.ps1" @args'+"`r`n"+'exit $LASTEXITCODE'
$cmd='@echo off'+"`r`n"+'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.ssh\GermanyRouter\StrictGermany\Invoke-ProtectedClaude.ps1" %*'+"`r`n"+'exit /b %errorlevel%'
$sh='#!/bin/sh'+"`n"+'exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$USERPROFILE/.ssh/GermanyRouter/StrictGermany/Invoke-ProtectedClaude.ps1" "$@"'+"`n"
foreach($folder in @($stable,$npm)) {
    foreach($name in 'claude.ps1','claude.cmd','claude') {
        $dest=Join-Path $folder $name
        if(Test-Path $dest){Copy-Item $dest (Join-Path $archive ((Split-Path $folder -Leaf)+'-'+$name))}
        $text=if($name -eq 'claude.ps1'){$ps}elseif($name -eq 'claude.cmd'){$cmd}else{$sh}
        [IO.File]::WriteAllText($dest,$text,[Text.UTF8Encoding]::new($false))
    }
}
$path=[Environment]::GetEnvironmentVariable('Path','User')
$parts=@($path -split ';' | Where-Object {$_ -and $_.TrimEnd('\') -ne $stable.TrimEnd('\')})
[Environment]::SetEnvironmentVariable('Path',(@($stable)+$parts -join ';'),'User')
Write-Output 'Installed durable Claude entry; proxy variables remain process-local. New terminals use the stable entry.'
