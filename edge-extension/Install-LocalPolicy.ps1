$ErrorActionPreference='Stop'
# Supported only on AD-domain joined Windows. Install one signed local extension;
# never write ProxySettings, Internet Settings, or replace another policy value.
if(-not (Get-CimInstance Win32_ComputerSystem).PartOfDomain){throw 'Local forced extension installation requires an AD joined Windows device'}
$target=Join-Path $env:LOCALAPPDATA 'LandingProxyConfigurator\EdgeSession'
$id=(Get-Content "$target\extension-id.txt").Trim()
if($id -notmatch '^[a-p]{32}$'){throw 'Invalid extension ID'}
foreach($file in 'package.crx','update.xml','native-host.json'){if(-not(Test-Path "$target\$file")){throw 'Packaged extension/native host missing'}}
$key='HKCU:\Software\Policies\Microsoft\Edge\ExtensionInstallForcelist'
New-Item -Path $key -Force|Out-Null
$values=Get-ItemProperty $key
$existing=@($values.PSObject.Properties|Where-Object {$_.Name -match '^\d+$' -and $_.Value -like ($id+';*')})
$n=if($existing.Count){$existing[0].Name}else{ $slot=1;while($values.PSObject.Properties.Name -contains "$slot"){$slot++};"$slot" }
$value=$id+';'+([uri](Join-Path $target 'update.xml')).AbsoluteUri
New-ItemProperty $key -Name $n -Value $value -PropertyType String -Force|Out-Null
if((Get-ItemPropertyValue $key $n) -ne $value){throw 'Policy readback failed'}
@{registry=$key;valueName=$n;extensionId=$id;value=$value;installedAt=[DateTime]::UtcNow.ToString('o')}|ConvertTo-Json|Set-Content "$target\installation.json"
