param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'App-Landing.Common.ps1')
Assert-AppLandingReady
$names = @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NO_PROXY')
$saved = @{}
foreach ($name in $names) {$saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try {
    Set-AppLandingEnvironment
    & claude @Arguments
    $code=$LASTEXITCODE
} finally {
    foreach ($name in $names) {[Environment]::SetEnvironmentVariable($name,$saved[$name],'Process')}
}
exit $code
