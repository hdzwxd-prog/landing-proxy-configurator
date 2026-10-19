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
