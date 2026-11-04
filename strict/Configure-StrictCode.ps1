$ErrorActionPreference='Stop'
$path=Join-Path $env:USERPROFILE '.claude\settings.json'
$settings=if(Test-Path $path){Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json}else{[pscustomobject]@{}}
if(Test-Path $path){Copy-Item -LiteralPath $path -Destination ($path+'.bak-'+(Get-Date -Format yyyyMMddHHmmssfff))}
if(-not $settings.env){$settings|Add-Member NoteProperty env ([pscustomobject]@{}) -Force}
foreach($name in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy')){
    $settings.env|Add-Member NoteProperty $name 'http://127.0.0.1:18485' -Force
}
foreach($name in @('NO_PROXY','no_proxy')){$settings.env|Add-Member NoteProperty $name '' -Force}
[IO.File]::WriteAllText($path,($settings|ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
Write-Output 'Claude Code application settings now use the strict Germany entry. Other keys preserved.'
