$ErrorActionPreference='Stop'
$target=Join-Path $env:LOCALAPPDATA 'LandingProxyConfigurator\EdgeSession'
$state=Get-Content "$target\installation.json" -Raw|ConvertFrom-Json
$key='HKCU:\Software\Policies\Microsoft\Edge\ExtensionInstallForcelist'
if($state.registry -ne $key -or $state.valueName -notmatch '^\d+$'){throw 'Invalid ownership receipt'}
$actual=Get-ItemPropertyValue $key $state.valueName -ErrorAction SilentlyContinue
if($actual -and $actual -ne $state.value){throw 'Policy value changed externally; refusing to remove it'}
if($actual){Remove-ItemProperty $key $state.valueName}
Write-Output 'Removed only this extension installation policy. Existing organization and proxy settings unchanged.'
