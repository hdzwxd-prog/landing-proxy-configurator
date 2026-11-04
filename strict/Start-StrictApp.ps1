param([ValidateSet('Firefox','Claude')][string]$App='Firefox',[switch]$NoDialog)
$ErrorActionPreference='Stop'
try {
    $root=Join-Path $env:USERPROFILE '.ssh\GermanyRouter\StrictGermany'
    $state=Get-Content (Join-Path $root 'isolation-install.json') -Raw | ConvertFrom-Json
    if(-not $state.ok){throw 'System network isolation is not installed; launch refused.'}
    & (Join-Path $root 'Start-StrictGermany.ps1')
    if($App -eq 'Firefox'){
        $exe=Join-Path $env:LOCALAPPDATA 'Programs\Mozilla Firefox\firefox.exe'
        $policy=Get-Content (Join-Path (Split-Path $exe) 'distribution\policies.json') -Raw | ConvertFrom-Json
        if(-not $policy.policies.Proxy.Locked -or $policy.policies.Proxy.Mode -ne 'manual' -or $policy.policies.Proxy.HTTPProxy -ne '127.0.0.1:18485' -or $policy.policies.Proxy.SSLProxy -ne '127.0.0.1:18485'){throw 'Firefox strict proxy policy is missing or changed.'}
        Start-Process -FilePath $exe
    } else {
        if(-not $state.claudeIncluded){throw 'Claude isolation is not yet installed.'}
        $package=Get-AppxPackage -Name Claude | Sort-Object Version -Descending | Select-Object -First 1
        $exe=Join-Path $package.InstallLocation 'app\claude.exe'
        if($exe -notin $state.targets){throw 'Claude was updated. Refresh and verify its network isolation before launching.'}
        $p=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Claude' -ErrorAction Stop
        if($p.egressProxyUrl -ne 'http://127.0.0.1:18485' -or $p.egressProxyPacUrl){throw 'Claude strict proxy policy is missing or changed.'}
        foreach($key in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')){[Environment]::SetEnvironmentVariable($key,'http://127.0.0.1:18485','Process')}
        $env:NO_PROXY=''
        Start-Process -FilePath $exe -ArgumentList '--proxy-server=http://127.0.0.1:18485','--disable-quic','--force-webrtc-ip-handling-policy=disable_non_proxied_udp'
    }
} catch {
    if($NoDialog){throw}
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'Germany-only proxy: launch blocked','OK','Warning')|Out-Null
    exit 1
}
