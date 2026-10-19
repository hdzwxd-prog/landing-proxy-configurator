param(
    [ValidateSet('Enable','Restore','Status')][string]$Action='Status',
    [switch]$AllowElevation,
    [string]$OwnerSid,
    [string]$ErrorFile
)
$ErrorActionPreference='Stop'
try {
    . (Join-Path $PSScriptRoot 'Edge-Policy.Common.ps1')
    $currentSid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if($OwnerSid -and $OwnerSid -ne $currentSid){throw '请使用当前 Windows 用户的管理员授权，不能将 Edge 配置写入其他账号。'}
    $regPath='Software\Policies\Microsoft\Edge'
    $statePath=Join-Path $env:USERPROFILE '.ssh\GermanyRouter\edge-policy-state.json'
    if($Action -eq 'Status') {
        $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($regPath)
        try {Read-EdgePolicyValues $key | ConvertTo-Json -Depth 5} finally{if($key){$key.Close()}}
        exit 0
    }
    if($Action -eq 'Enable') {
        . (Join-Path $PSScriptRoot 'App-Landing.Common.ps1')
        Assert-AppLandingReady
        $machine=[Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($regPath)
        try {
            if($machine -and @($machine.GetValueNames() | Where-Object {$_ -in @('ProxySettings','ProxyMode','ProxyServer','ProxyPacUrl','ProxyBypassList','WebRtcLocalhostIpHandling','QuicAllowed','DefaultGeolocationSetting')}).Count){throw '检测到计算机级 Edge 管理策略；未覆盖，请先由管理员确认现有策略。'}
        }finally{if($machine){$machine.Close()}}
    }
    $key=$null
    try {$key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($regPath)}
    catch {
        $denied=$_.Exception.ToString() -match 'UnauthorizedAccessException|SecurityException'
        if(-not $AllowElevation -or -not $denied){throw}
        $errorPath=Join-Path $env:TEMP ('landing-edge-'+[guid]::NewGuid().ToString('N')+'.txt')
        $arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Action '+$Action+' -OwnerSid "'+$currentSid+'" -ErrorFile "'+$errorPath+'"'
        $child=Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
        if(-not $child.WaitForExit(120000)){throw '管理员授权仍未完成。请完成系统提示后刷新配置器。'}
        if($child.ExitCode -ne 0){
            $detail=if(Test-Path -LiteralPath $errorPath){Get-Content -LiteralPath $errorPath -Raw -Encoding UTF8}else{'Windows 管理员授权未完成，Edge 设置未启用。'}
            throw $detail
        }
        if(Test-Path -LiteralPath $errorPath){Remove-Item -LiteralPath $errorPath}
        exit 0
    }
    $mutex=[Threading.Mutex]::new($false,'Local\LandingEdgePolicy')
    $locked=$false
    try {
        try {$locked=$mutex.WaitOne(1000)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw '另一个 Edge 设置操作尚未结束，请稍后再试。'}
        Set-EdgeLandingPolicy -Action $Action -Key $key -StatePath $statePath
    }finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose();$key.Close()}
    Write-Output 'Edge 策略已写入。请在保存网页工作后完整退出并重开 Edge；代理刷新和隐私策略生效时间不同。'
} catch {
    if($ErrorFile){[IO.File]::WriteAllText($ErrorFile,$_.Exception.Message,[Text.UTF8Encoding]::new($false))}
    Write-Error $_.Exception.Message
    exit 1
}
