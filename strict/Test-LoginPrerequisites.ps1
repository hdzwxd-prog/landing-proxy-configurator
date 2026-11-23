$ErrorActionPreference='Stop'
try {
    $browser=Join-Path $env:LOCALAPPDATA 'Programs\Mozilla Firefox\firefox.exe'
    $p=(Get-Content (Join-Path (Split-Path $browser) 'distribution\policies.json') -Raw | ConvertFrom-Json).policies
    if(-not $p.Proxy.Locked -or $p.Proxy.Mode -ne 'manual' -or $p.Proxy.HTTPProxy -ne '127.0.0.1:18485' -or $p.Proxy.SSLProxy -ne '127.0.0.1:18485' -or $p.Proxy.Passthrough -or $p.Preferences.'network.proxy.failover_direct'.Value -ne $false -or $p.Preferences.'network.proxy.failover_direct'.Status -ne 'locked'){throw 'Firefox strict proxy policy mismatch'}
    & "$PSScriptRoot\Start-StrictGermany.ps1" -CheckOnly
    exit 0
} catch { Write-Error 'Login prerequisites failed. No browser launched.'; exit 1 }
