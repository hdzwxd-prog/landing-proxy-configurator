param([string]$OutputPath = (Join-Path $PSScriptRoot 'bin\LandingProxyConfigurator.exe'))
$ErrorActionPreference = 'Stop'
$folder = Split-Path $OutputPath -Parent
New-Item -ItemType Directory -Path $folder -Force | Out-Null
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe "/win32manifest:$PSScriptRoot\app.manifest" "/out:$OutputPath" /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Net.Http.dll (Join-Path $PSScriptRoot 'GermanyProxyManager.cs')
if ($LASTEXITCODE -ne 0) { throw 'C# build failed' }
Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256
