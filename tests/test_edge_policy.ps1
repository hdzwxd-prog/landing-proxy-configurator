$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\Edge-Policy.Common.ps1')
function Assert($condition,$message){if(-not $condition){throw $message}}
$id=[guid]::NewGuid().ToString('N')
$keyPath='Software\LandingProxyPolicyTests\'+$id
$statePath=Join-Path $env:TEMP ('landing-edge-test-'+$id+'.json')
$key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($keyPath)
try {
    $key.SetValue('Unrelated','preserve')
    $key.SetValue('ProxySettings','{"ProxyMode":"system"}')
    $key.SetValue('QuicAllowed',1,[Microsoft.Win32.RegistryValueKind]::DWord)
    Set-EdgeLandingPolicy Enable $key $statePath
    Assert ($key.GetValue('ProxySettings') -like '*18484*') 'Enable did not apply'
    $first=Get-Content $statePath -Raw -Encoding UTF8
    Set-EdgeLandingPolicy Enable $key $statePath
    Assert ($first -eq (Get-Content $statePath -Raw -Encoding UTF8)) 'Idempotent enable overwrote backup'
    Assert ($key.GetValue('Unrelated') -eq 'preserve') 'Unrelated value changed'
    $key.DeleteValue('ProxySettings')
    $missingRejected=$false
    try{Set-EdgeLandingPolicy Enable $key $statePath}catch{$missingRejected=$true}
    Assert $missingRejected 'Missing policy must not be silently overwritten'
    Set-EdgeLandingPolicy Enable $key $statePath -RepairMissingProxy
    Assert ($key.GetValue('ProxySettings') -like '*18484*') 'Explicit repair failed'
    Assert ($first -eq (Get-Content $statePath -Raw -Encoding UTF8)) 'Repair destroyed original backup'
    Set-EdgeLandingPolicy Restore $key $statePath
    Assert ($key.GetValue('ProxySettings') -eq '{"ProxyMode":"system"}') 'Original proxy not restored'
    Assert ($key.GetValue('QuicAllowed') -eq 1) 'Original DWORD not restored'
    Assert ($key.GetValueNames() -notcontains 'WebRtcLocalhostIpHandling') 'Previously absent setting was not removed'
    Set-EdgeLandingPolicy Restore $key $statePath
    Set-EdgeLandingPolicy Enable $key $statePath
    $key.SetValue('ProxySettings','{"ProxyMode":"direct"}')
    $conflict=$false
    try{Set-EdgeLandingPolicy Restore $key $statePath}catch{$conflict=$true}
    Assert $conflict 'External change should prevent restoration'
    Assert ($key.GetValue('ProxySettings') -eq '{"ProxyMode":"direct"}') 'External setting was overwritten'
    'PASS: enable, idempotency, restore original types, remove absent values, preserve unrelated settings, conflict protection'
} finally {
    $key.Close()
    # Exact randomly generated disposable key; never production policies.
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($keyPath)
    Get-ChildItem -LiteralPath $env:TEMP -File -Filter ('landing-edge-test-'+$id+'.json*') | Remove-Item
}
