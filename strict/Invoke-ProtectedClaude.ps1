$ErrorActionPreference='Stop'
# Called from npm shims in a child PowerShell. Never changes the caller's environment.
$root=Join-Path $env:USERPROFILE '.ssh\GermanyRouter\StrictGermany'
$exe=Join-Path $env:APPDATA 'npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe'
$browser=Join-Path $env:LOCALAPPDATA 'Programs\Mozilla Firefox\firefox.exe'
try {
    $receipt=Get-Content (Join-Path $root 'cli-isolation.json') -Raw | ConvertFrom-Json
    $stream=[IO.File]::OpenRead($exe)
    $sha=[Security.Cryptography.SHA256]::Create()
    try {$hash=[BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','')} finally {$stream.Dispose();$sha.Dispose()}
    if(-not $receipt.ok -or $receipt.exe -ne $exe -or $receipt.hash -ne $hash){throw 'CLI protection missing or executable updated. Login blocked until protection is verified.'}
    $p=(Get-Content (Join-Path (Split-Path $browser) 'distribution\policies.json') -Raw | ConvertFrom-Json).policies
    if(-not $p.Proxy.Locked -or $p.Proxy.Mode -ne 'manual' -or $p.Proxy.HTTPProxy -ne '127.0.0.1:18485' -or $p.Proxy.SSLProxy -ne '127.0.0.1:18485' -or $p.Proxy.Passthrough -or $p.Preferences.'network.proxy.failover_direct'.Value -ne $false -or $p.Preferences.'network.proxy.failover_direct'.Status -ne 'locked'){throw 'Firefox strict proxy policy mismatch; login blocked.'}
    foreach($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')){[Environment]::SetEnvironmentVariable($key,'http://127.0.0.1:18485','Process')}
    $env:NO_PROXY='localhost,127.0.0.1,::1'
    $env:BROWSER=Join-Path $root 'ProtectedAuthBrowser.exe'
    if(-not(Test-Path -LiteralPath $env:BROWSER)){throw 'Protected browser dispatcher missing'}
    if($args -notcontains '--help' -and $args -notcontains '--version') { & (Join-Path $root 'Start-StrictGermany.ps1') -CheckOnly }
    if($args.Count -ge 2 -and $args[0] -eq 'auth' -and $args[1] -eq 'login' -and $args -notcontains '--help') {
        Write-Host 'Germany-only login: Firefox will open. Paste the displayed authorization code back into this terminal.'
    }
    & $exe @args
    exit $LASTEXITCODE
} catch { [Console]::Error.WriteLine('Login/start blocked: '+$_.Exception.Message); exit 1 }
