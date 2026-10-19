$ErrorActionPreference = 'Stop'
function Assert-AppLandingReady {
    $routerDir = Join-Path $env:USERPROFILE '.ssh\GermanyRouter'
    . (Join-Path $routerDir 'Landing.Common.ps1')
    if (-not (Test-LandingListener 18484)) { throw '落地代理未运行。请先启动上游客户端，再在落地代理配置器中启用转发。' }
    if (-not (Test-LandingExit (Get-LandingChoice))) { throw '所选落地出口检测未通过，已取消启动；请在配置器中检测出口。' }
}
function Set-AppLandingEnvironment {
    # Child process only: never modify user/machine environment or WinINET.
    foreach ($name in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')) {
        [Environment]::SetEnvironmentVariable($name, 'http://127.0.0.1:18484', 'Process')
    }
    $env:NO_PROXY = 'localhost,127.0.0.1,::1,.local'
}
function Set-EdgeLandingPrivacy([string]$profile) {
    $default=Join-Path $profile 'Default'
    New-Item -ItemType Directory -Path $default -Force | Out-Null
    $path=Join-Path $default 'Preferences'
    $prefs=if(Test-Path $path){Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json}else{[pscustomobject]@{}}
    if(-not $prefs.webrtc){$prefs|Add-Member NoteProperty webrtc ([pscustomobject]@{}) -Force}
    $prefs.webrtc | Add-Member NoteProperty ip_handling_policy 'disable_non_proxied_udp' -Force
    if(-not $prefs.profile){$prefs|Add-Member NoteProperty profile ([pscustomobject]@{}) -Force}
    if(-not $prefs.profile.default_content_setting_values){$prefs.profile|Add-Member NoteProperty default_content_setting_values ([pscustomobject]@{}) -Force}
    $prefs.profile.default_content_setting_values | Add-Member NoteProperty geolocation 2 -Force
    if(Test-Path $path){Copy-Item -LiteralPath $path -Destination ($path+'.bak-'+(Get-Date -Format 'yyyyMMdd-HHmmssfff'))}
    [IO.File]::WriteAllText($path,($prefs|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
}
