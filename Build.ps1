param([string]$OutputPath = (Join-Path $PSScriptRoot 'bin\LandingProxyConfigurator.exe'))
$ErrorActionPreference = 'Stop'
$folder = Split-Path $OutputPath -Parent
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe "/win32manifest:$PSScriptRoot\app.manifest" "/out:$OutputPath" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Net.Http.dll /r:System.Web.Extensions.dll (Join-Path $PSScriptRoot 'GermanyProxyManager.cs') (Join-Path $PSScriptRoot 'EdgeExitProbe.cs') (Join-Path $PSScriptRoot 'StrictPanel.cs') (Join-Path $PSScriptRoot 'EdgeSessionLease.cs') (Join-Path $PSScriptRoot 'EdgeSessionControl.cs')
if ($LASTEXITCODE -ne 0) { throw 'C# build failed' }
Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256

& $compiler /nologo /target:exe ("/out:" + (Join-Path $folder 'LandingEdgeNativeHost.exe')) (Join-Path $PSScriptRoot 'edge-extension\NativeHost.cs')
if ($LASTEXITCODE -ne 0) { throw 'Native messaging host build failed' }

& $compiler /nologo /target:exe ("/out:" + (Join-Path $folder 'EdgeProbeCli.exe')) /r:System.Web.Extensions.dll (Join-Path $PSScriptRoot 'EdgeExitProbe.cs') (Join-Path $PSScriptRoot 'diagnostics\EdgeProbeCli.cs')
if ($LASTEXITCODE -ne 0) { throw 'Edge exit probe build failed' }
