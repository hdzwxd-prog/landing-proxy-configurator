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
    if($Action -eq 'Restore' -and (-not $state -or -not $state.enabled)){return}
    if($Action -eq 'Enable' -and $state -and $state.enabled) {
        foreach($name in $script:EdgeLandingValues.Keys){
            if($RepairMissingProxy -and $name -eq 'ProxySettings' -and -not $before[$name].exists){continue}
            if(-not $before[$name].exists -or $before[$name].kind -ne $script:EdgeLandingValues[$name].kind -or $before[$name].value -cne $script:EdgeLandingValues[$name].value){throw 'Edge 设置已被其他程序修改，请先检查策略，未覆盖现有更改。'}
        }
        if($RepairMissingProxy -and -not $before['ProxySettings'].exists){
            $Key.SetValue('ProxySettings',$script:EdgeLandingValues['ProxySettings'].value,[Microsoft.Win32.RegistryValueKind]::String)
            $Key.Flush()
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
        foreach($name in $script:EdgeLandingValues.Keys){
            $original=$state.original.$name
            if(-not $original){throw 'Edge 原设置备份不完整；未修改策略。'}
            $sameOriginal=($before[$name].exists -eq $original.exists -and (-not $original.exists -or ($before[$name].kind -eq $original.kind -and $before[$name].value -ceq $original.value)))
            $sameOurs=($before[$name].exists -and $before[$name].kind -eq $script:EdgeLandingValues[$name].kind -and $before[$name].value -ceq $script:EdgeLandingValues[$name].value)
            if(-not $sameOriginal -and -not $sameOurs){throw 'Edge 策略已被其他程序修改；为保留新设置，未执行恢复。'}
            $target[$name]=@{exists=$original.exists;kind=$original.kind;value=$original.value}
        }
    }
    try {
        Write-EdgePolicyValues $Key $target
        $state.enabled=($Action -eq 'Enable');$state.pending=$false
        $state.appliedAt=[DateTime]::UtcNow.ToString('o')
        Save-EdgePolicyState $StatePath $state
    } catch {
        Write-EdgePolicyValues $Key $before
        if($Action -eq 'Enable'){$state.enabled=$false;$state.pending=$false;Save-EdgePolicyState $StatePath $state}
        throw
    }
}
