param([Parameter(Mandatory=$true)][ValidateSet('clash','wanda')][string]$Choice,
      [string]$Endpoint='127.0.0.1:7980',
      [Parameter(Mandatory=$true)][ValidateSet('germany','nas04')][string]$Landing,
      [string]$RouterDir=(Join-Path $env:USERPROFILE '.ssh\GermanyRouter'))
$ErrorActionPreference='Stop'
if ($Choice -eq 'clash') {
    if ($Endpoint -notmatch '^127\.0\.0\.1:(\d+)$') { throw '上游须为本机 HTTP / 混合端口：127.0.0.1:端口。' }
    $port=[int]$Matches[1]
    if ($port -lt 1 -or $port -gt 65535 -or $port -in @(18484,18485,18583,18584,19090)) { throw '上游端口无效或指向落地自身。' }
}
$mutex=[Threading.Mutex]::new($false,'Local\IntegratedLandingRoute')
$held=$false
try {
    try{$held=$mutex.WaitOne(30000)}catch [Threading.AbandonedMutexException]{$held=$true}
    if(-not $held){throw '另一个配置操作正在进行。'}
    if ((Get-Content (Join-Path $RouterDir 'mode.txt') -Raw).Trim() -eq 'off') {
        throw '请先启用转发模式，再应用统一配置。'
    }
    $oldChoice=(Get-Content (Join-Path $RouterDir 'upstream-choice.txt') -Raw).Trim()
    if($oldChoice -notin @('clash','wanda')){$oldChoice='clash'}
    $oldEndpoint=(Get-Content (Join-Path $RouterDir 'clash-upstream.txt') -Raw).Trim()
    $oldLanding=(Get-Content (Join-Path $RouterDir 'landing-choice.txt') -Raw).Trim()
    $strict=Join-Path $RouterDir 'StrictGermany'
    $hasStrict=Test-Path (Join-Path $strict 'isolation-install.json')
    if($hasStrict){
        $oldStrictConfig=[IO.File]::ReadAllBytes((Join-Path $strict 'config.json'))
        $oldStrictChoice=[IO.File]::ReadAllBytes((Join-Path $strict 'upstream-choice.txt'))
        $oldEnabled=(Get-Content (Join-Path $strict 'enabled.txt') -Raw).Trim()
    }
    $touchedNormal=$false;$touchedStrict=$false
    try {
        $touchedNormal=$true
        & (Join-Path $RouterDir 'Set-Germany-Upstream.ps1') -Choice $Choice -Endpoint $Endpoint -Landing $Landing -RouterDir $RouterDir
        if($hasStrict){
            $touchedStrict=$true
            & (Join-Path $strict 'Set-StrictUpstream.ps1') -Choice $Choice -Endpoint $Endpoint
        }
        Write-Output '统一配置已应用。Firefox/Claude 的德国出口规则保持锁定。'
    } catch {
        $failure=$_.Exception.Message;$errors=@()
        if($touchedStrict){
            try {
                & (Join-Path $strict 'Set-StrictUpstream.ps1') -Stop
                [IO.File]::WriteAllBytes((Join-Path $strict 'config.json'),$oldStrictConfig)
                [IO.File]::WriteAllBytes((Join-Path $strict 'upstream-choice.txt'),$oldStrictChoice)
                Set-Content (Join-Path $strict 'enabled.txt') $oldEnabled -Encoding ASCII
                if($oldEnabled -eq 'true'){& (Join-Path $strict 'Start-StrictGermany.ps1')}
            }catch{$errors+='德国应用入口恢复未通过'}
        }
        if($touchedNormal){
            try {
                & (Join-Path $RouterDir 'Set-Germany-Upstream.ps1') -Choice $oldChoice -Endpoint $oldEndpoint -Landing $oldLanding -RouterDir $RouterDir
            }catch{$errors+='常规入口恢复未通过'}
        }
        if($errors.Count){throw ($failure+'；'+($errors -join '；')+'。请检测实际出口，未宣告成功。')}
        throw ($failure+'；已恢复操作前配置。')
    }
}finally{if($held){$mutex.ReleaseMutex()};$mutex.Dispose()}
