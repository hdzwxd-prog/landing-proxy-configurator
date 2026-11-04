param([ValidateSet('clash','wanda')][string]$Choice,[string]$Endpoint='127.0.0.1:7980',[switch]$Stop)
$ErrorActionPreference='Stop'
$root=Join-Path $env:USERPROFILE '.ssh\GermanyRouter\StrictGermany'
$mutex=[Threading.Mutex]::new($false,'Local\StrictGermanyRoute18485')
$held=$false
try {
    try{$held=$mutex.WaitOne(30000)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){throw 'Another Germany-only operation is in progress.'}
    $exe=Join-Path $root 'strict-germany-core.exe'
    $listener=Get-NetTCPConnection -LocalPort 18485 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if($listener){$p=Get-Process -Id $listener.OwningProcess;if($p.Path -ne $exe){throw 'Unexpected port owner; refused.'}}
    $path=Join-Path $root 'config.json'
    if(-not $Stop){
        if(-not $Choice){throw 'Explicit channel choice required'}
        $endpointValue=if($Choice -eq 'wanda'){'127.0.0.1:7892'}else{$Endpoint.Trim()}
        if($endpointValue -notmatch '^127\.0\.0\.1:(\d+)$'){throw 'Only local HTTP/mixed upstreams are supported'}
        $port=[int]$Matches[1]
        if($port -lt 1 -or $port -gt 65535 -or $port -in @(18484,18485,18583,18584,19090)){throw 'Invalid or recursive upstream port'}
        $config=Get-Content $path -Raw | ConvertFrom-Json
        if(@($config.rules).Count -ne 1 -or $config.rules[0] -ne 'MATCH,Germany-VLESS'){throw 'Strict routing invariant changed'}
        $upstream=@($config.proxies | Where-Object name -eq 'STRICT-UPSTREAM')[0]
        if(-not $upstream){throw 'Strict upstream missing'}
        $upstream.server='127.0.0.1';$upstream.port=$port
        $newPath=$path+'.pending'
        [IO.File]::WriteAllText($newPath,($config|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
        & $exe -t -d $root -f $newPath 2>&1 | Out-Null
        if($LASTEXITCODE -ne 0){Remove-Item -LiteralPath $newPath;throw 'Candidate configuration rejected'}
        Copy-Item -LiteralPath $path -Destination ($path+'.previous') -Force
        Move-Item -LiteralPath $newPath -Destination $path -Force
        Set-Content (Join-Path $root 'upstream-choice.txt') $Choice -Encoding ASCII
    }
    if($listener){Stop-Process -Id $p.Id -ErrorAction Stop; $p.WaitForExit(5000)|Out-Null}
    if($Stop){Set-Content (Join-Path $root 'enabled.txt') 'false' -Encoding ASCII;Write-Output 'Germany-only stopped; Firefox and Claude remain network-restricted.';exit 0}
    Set-Content (Join-Path $root 'enabled.txt') 'true' -Encoding ASCII
    # Keep the user's explicit choice even on failure. Never select a working alternate.
    & (Join-Path $root 'Start-StrictGermany.ps1')
} finally {if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
