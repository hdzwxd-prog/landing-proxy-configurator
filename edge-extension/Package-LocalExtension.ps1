$ErrorActionPreference='Stop'
$target=Join-Path $env:LOCALAPPDATA 'LandingProxyConfigurator\EdgeSession'
$stage=Join-Path $target 'package'
New-Item -ItemType Directory -Force $stage|Out-Null
foreach($name in 'manifest.json','background.js','controller.mjs'){Copy-Item (Join-Path $PSScriptRoot $name) $stage -Force}
$manifest=Get-Content "$stage\manifest.json" -Raw|ConvertFrom-Json
$manifest|Add-Member NoteProperty update_url ([uri](Join-Path $target 'update.xml')).AbsoluteUri -Force
[IO.File]::WriteAllText("$stage\manifest.json",($manifest|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$packArgs=@('--pack-extension="'+$stage+'"','--user-data-dir="'+(Join-Path $target 'pack-profile')+'"','--no-startup-window')
if(Test-Path "$target\package.pem"){$packArgs+=('--pack-extension-key="'+$target+'\package.pem"')}
if(Test-Path "$target\package.crx"){Copy-Item "$target\package.crx" "$target\package.previous.crx" -Force;Remove-Item -LiteralPath "$target\package.crx"}
$p=Start-Process "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" -WindowStyle Hidden -ArgumentList $packArgs -PassThru -Wait
if($p.ExitCode -ne 0 -or -not(Test-Path "$target\package.crx")){throw 'Edge extension packaging failed'}
$pem=Join-Path $target 'package.pem'
$acl=Get-Acl $pem;$acl.SetAccessRuleProtection($true,$false)
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.WindowsIdentity]::GetCurrent().User,'FullControl','Allow'));Set-Acl $pem $acl
# Derive only the PUBLIC extension identity. Never print/copy the private signing key.
@'
from pathlib import Path
import os,hashlib,json
from cryptography.hazmat.primitives import serialization
p=Path(os.environ['LOCALAPPDATA'])/'LandingProxyConfigurator/EdgeSession'
k=serialization.load_pem_private_key((p/'package.pem').read_bytes(),None)
pub=k.public_key().public_bytes(serialization.Encoding.DER,serialization.PublicFormat.SubjectPublicKeyInfo)
eid=''.join(chr(ord('a')+int(c,16)) for c in hashlib.sha256(pub).hexdigest()[:32])
(p/'extension-id.txt').write_text(eid)
version=json.loads((p/'package/manifest.json').read_text(encoding='utf-8-sig'))['version']
(p/'update.xml').write_text('<?xml version="1.0" encoding="UTF-8"?><gupdate xmlns="http://www.google.com/update2/response" protocol="2.0"><app appid="'+eid+'"><updatecheck codebase="'+(p/'package.crx').as_uri()+'" version="'+version+'" /></app></gupdate>')
'@ | python -
if($LASTEXITCODE -ne 0){throw 'Extension identity/update manifest generation failed'}
& "$PSScriptRoot\Install-NativeHost.ps1" -ExtensionId (Get-Content "$target\extension-id.txt").Trim()
