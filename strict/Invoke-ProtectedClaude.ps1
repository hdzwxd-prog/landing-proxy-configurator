$ErrorActionPreference='Stop'
# Called from npm shims in a child PowerShell. Never changes the caller's environment.
$root=Join-Path $env:USERPROFILE '.ssh\GermanyRouter\StrictGermany'
$exe=Join-Path $env:APPDATA 'npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe'
$browser=Join-Path $env:LOCALAPPDATA 'Programs\Mozilla Firefox\firefox.exe'
try {
    $receipt=Get-Content (Join-Path $root 'cli-isolation.json') -Raw | ConvertFrom-Json
    if(-not $receipt.ok -or $receipt.exe -ne $exe -or $receipt.hash -ne (Get-FileHash -LiteralPath $exe).Hash){throw 'CLI protection missing or executable updated. Login blocked until protection is verified.'}
    $p=(Get-Content (Join-Path (Split-Path $browser) 'distribution\policies.json') -Raw | ConvertFrom-Json).policies
    if(-not $p.Proxy.Locked -or $p.Proxy.Mode -ne 'manual' -or $p.Proxy.HTTPProxy -ne '127.0.0.1:18485' -or $p.Proxy.SSLProxy -ne '127.0.0.1:18485' -or $p.Proxy.Passthrough -or $p.Preferences.'network.proxy.failover_direct'.Value -ne $false -or $p.Preferences.'network.proxy.failover_direct'.Status -ne 'locked'){throw 'Firefox strict proxy policy mismatch; login blocked.'}
    foreach($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')){[Environment]::SetEnvironmentVariable($key,'http://127.0.0.1:18485','Process')}
    $env:NO_PROXY='localhost,127.0.0.1,::1'
    $env:BROWSER=$browser
    if($args -notcontains '--help' -and $args -notcontains '--version') { & (Join-Path $root 'Start-StrictGermany.ps1') -CheckOnly }
    & $exe @args
    exit $LASTEXITCODE
} catch { Write-Error $_.Exception.Message; exit 1 }
