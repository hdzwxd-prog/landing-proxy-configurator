$ErrorActionPreference = 'Stop'
$script:EdgeLandingValues = [ordered]@{
    ProxySettings = @{kind='String'; value='{"ProxyMode":"fixed_servers","ProxyServer":"http://127.0.0.1:18484","ProxyBypassList":"<-loopback>"}'}
    WebRtcLocalhostIpHandling = @{kind='String'; value='disable_non_proxied_udp'}
    QuicAllowed = @{kind='DWord'; value=0}
    DefaultGeolocationSetting = @{kind='DWord'; value=2}
}
function Read-EdgePolicyValues($Key) {
    $result=[ordered]@{}
    foreach($name in $script:EdgeLandingValues.Keys) {
        $exists=$Key -and ($Key.GetValueNames() -contains $name)
        $result[$name]=@{exists=[bool]$exists; kind=$(if($exists){$Key.GetValueKind($name).ToString()}else{'String'}); value=$(if($exists){$Key.GetValue($name)}else{$null})}
    }
    return $result
}
function Write-EdgePolicyValues($Key,$Values) {
    foreach($name in $script:EdgeLandingValues.Keys) {
        $item=$Values[$name]
        if($item.exists){$Key.SetValue($name,$item.value,[Microsoft.Win32.RegistryValueKind]::$($item.kind))}
        else {$Key.DeleteValue($name,$false)}
    }
    $Key.Flush()
}
function Save-EdgePolicyState($Path,$State) {
    $folder=Split-Path $Path -Parent
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $tmp=$Path+'.tmp-'+[guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($tmp,($State|ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    if(Test-Path -LiteralPath $Path){[IO.File]::Replace($tmp,$Path,($Path+'.bak-'+(Get-Date -Format 'yyyyMMdd-HHmmssfff')))}
    else{[IO.File]::Move($tmp,$Path)}
}
function Set-EdgeLandingPolicy {
    param([ValidateSet('Enable','Restore')]$Action,$Key,[string]$StatePath,[switch]$RepairMissingProxy)
    $before=Read-EdgePolicyValues $Key
    $state=if(Test-Path -LiteralPath $StatePath){Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8|ConvertFrom-Json}else{$null}
    if($Action -eq 'Restore' -and -not $state){return}
    if($Action -eq 'Enable' -and $state -and $state.enabled) {
        # Explicit re-enable may encounter any mix of our policy and the
        # original values after a restore or interrupted operation.
        $target=[ordered]@{}
        $needsWrite=$false
        foreach($name in $script:EdgeLandingValues.Keys){
            $ours=$script:EdgeLandingValues[$name]
            $actual=$before[$name]
            $original=$state.original.$name
            if(-not $original){throw "Edge 原设置备份缺少 $name，请检查备份。"}
            $sameOurs=$actual.exists -and $actual.kind -eq $ours.kind -and $actual.value -ceq $ours.value
            $sameOriginal=$actual.exists -eq $original.exists -and (-not $actual.exists -or ($actual.kind -eq $original.kind -and $actual.value -ceq $original.value))
            $missingProxy=$RepairMissingProxy -and $name -eq 'ProxySettings' -and -not $actual.exists
            if(-not ($sameOurs -or $sameOriginal -or $missingProxy)){throw "Edge 策略 $name 与落地设置及原备份均不一致。请在 edge://policy 核对该项。"}
            if(-not $sameOurs){$needsWrite=$true}
            $target[$name]=@{exists=$true;kind=$ours.kind;value=$ours.value}
        }
        try {
            if($needsWrite){Write-EdgePolicyValues $Key $target}
            if($state.pending){$state.pending=$false;Save-EdgePolicyState $StatePath $state}
        } catch {
            if($needsWrite){Write-EdgePolicyValues $Key $before}
            throw
        }
        return
    }
    $target=[ordered]@{}
    if($Action -eq 'Enable') {
        foreach($name in $script:EdgeLandingValues.Keys){$target[$name]=@{exists=$true;kind=$script:EdgeLandingValues[$name].kind;value=$script:EdgeLandingValues[$name].value}}
        # Persist originals BEFORE touching the registry, including interrupted enable attempts.
        $state=[pscustomobject]@{enabled=$true;appliedAt=[DateTime]::UtcNow.ToString('o');original=$before;pending=$true}
        Save-EdgePolicyState $StatePath $state
    } else {
        $needsRestore=$false
        foreach($name in $script:EdgeLandingValues.Keys){
            $original=$state.original.$name
            if(-not $original){throw 'Edge 原设置备份不完整；未修改策略。'}
            $sameOriginal=($before[$name].exists -eq $original.exists -and (-not $original.exists -or ($before[$name].kind -eq $original.kind -and $before[$name].value -ceq $original.value)))
            $sameOurs=($before[$name].exists -and $before[$name].kind -eq $script:EdgeLandingValues[$name].kind -and $before[$name].value -ceq $script:EdgeLandingValues[$name].value)
            if(-not $sameOriginal -and -not $sameOurs){throw 'Edge 策略已被其他程序修改；为保留新设置，未执行恢复。'}
            if(-not $sameOriginal){$needsRestore=$true}
            $target[$name]=@{exists=$original.exists;kind=$original.kind;value=$original.value}
        }
        if(-not $state.enabled -and -not $state.pending -and -not $needsRestore){return}
    }
    try {
        Write-EdgePolicyValues $Key $target
        $readback=Read-EdgePolicyValues $Key
        foreach($name in $target.Keys){
            $v=$readback[$name];$expected=$target[$name]
            if($v.exists -ne $expected.exists -or ($v.exists -and ($v.kind -ne $expected.kind -or $v.value -cne $expected.value))){throw "Edge 策略 $name 写入后核验失败。"}
        }
        $state.enabled=($Action -eq 'Enable');$state.pending=$false
        $state.appliedAt=[DateTime]::UtcNow.ToString('o')
        Save-EdgePolicyState $StatePath $state
    } catch {
        Write-EdgePolicyValues $Key $before
        if($Action -eq 'Enable'){$state.enabled=$false;$state.pending=$false;Save-EdgePolicyState $StatePath $state}
        throw
    }
}
