param([ValidateSet('Enable','Restore','Status')][string]$Action = 'Enable')
$ErrorActionPreference = 'Stop'
$stateDir = Join-Path $env:USERPROFILE '.ssh\GermanyRouter'
$stateFile = Join-Path $stateDir 'claude-landing-config.json'
$proxy = 'http://127.0.0.1:18484'
function Write-JsonFile($path,$value) {
    [IO.File]::WriteAllText($path,($value | ConvertTo-Json -Depth 100),[Text.UTF8Encoding]::new($false))
}
if ($Action -eq 'Status') {
    if (Test-Path $stateFile) {Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json | Select-Object enabled,appliedAt}
    exit 0
}
if ($Action -eq 'Restore') {
    if (-not (Test-Path $stateFile)) {throw '没有本程序保存的 Claude 设置。'}
    $state=Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $config=Get-Content $state.configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach($name in @('egressProxyUrl','egressProxyPacUrl')) {
        if ($state.original.$name.exists) {$config | Add-Member NoteProperty $name $state.original.$name.value -Force}
        else {$config.PSObject.Properties.Remove($name)}
    }
    Copy-Item -LiteralPath $state.configPath -Destination ($state.configPath+'.bak-'+(Get-Date -Format 'yyyyMMdd-HHmmssfff'))
    Write-JsonFile $state.configPath $config
    $state.enabled=$false;Write-JsonFile $stateFile $state
    Write-Output 'Claude 原代理设置已恢复；完全退出并重开 Claude 后生效。'
    exit 0
}
$package=Get-AppxPackage -Name 'Claude' | Sort-Object Version -Descending | Select-Object -First 1
if ($package -and [version]$package.Version -lt [version]'1.44121.1') {throw '请先升级 Claude。当前版本不支持专用代理配置。'}
# Managed policy takes precedence as a group. Do not pretend a local file overrides it.
foreach($hive in @('HKLM','HKCU')) {
    $key=Get-Item -LiteralPath ($hive+':\Software\Policies\Claude') -ErrorAction SilentlyContinue
    if ($key -and $key.GetValueNames().Count -gt 0) {throw '存在 Claude 管理策略，需核对策略优先级后再设置；未覆盖现有策略。'}
}
$library=Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary'
# This app-behavior library uses LocalAppData directly, even in the tested MSIX
# build. Do not confuse it with the virtualized Roaming Claude account data.
New-Item -ItemType Directory -Path $stateDir,$library -Force | Out-Null
$metaPath=Join-Path $library '_meta.json'
$meta=if(Test-Path $metaPath){Get-Content $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json}else{[pscustomobject]@{}}
if ($meta.hybridPointer) {throw 'Claude 使用远程配置管理；未修改其配置来源。'}
if ($meta.appliedId) {
    if($meta.appliedId -notmatch '^[a-f0-9-]{36}$'){throw 'Claude 本地配置 ID 无效。'}
    $configPath=Join-Path $library ($meta.appliedId+'.json')
    if(-not(Test-Path $configPath)){throw 'Claude 当前配置文件缺失；未替换。'}
    $config=Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
    $id=[Guid]::NewGuid().ToString()
    $configPath=Join-Path $library ($id+'.json')
    $config=[pscustomobject]@{}
    $meta | Add-Member NoteProperty appliedId $id -Force
}
$original=@{}
foreach($name in @('egressProxyUrl','egressProxyPacUrl')) {
    $p=$config.PSObject.Properties[$name]
    $original[$name]=@{exists=($null -ne $p);value=if($p){$p.Value}else{$null}}
}
$prior=if(Test-Path $stateFile){Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json}else{$null}
if ($prior -and $prior.configPath -eq $configPath) {$original=$prior.original}
$stamp=Get-Date -Format 'yyyyMMdd-HHmmssfff'
foreach($path in @($metaPath,$configPath)) {if(Test-Path $path){Copy-Item -LiteralPath $path -Destination ($path+'.bak-'+$stamp)}}
$config | Add-Member NoteProperty egressProxyUrl $proxy -Force
$config.PSObject.Properties.Remove('egressProxyPacUrl')
Write-JsonFile $configPath $config
Write-JsonFile $metaPath $meta
$at=[DateTime]::UtcNow.ToString('o')
Write-JsonFile $stateFile @{enabled=$true;appliedAt=$at;configPath=$configPath;original=$original}
Set-Content -LiteralPath (Join-Path $stateDir 'claude-policy-applied.txt') -Value $at -Encoding ASCII
Write-Output 'Claude 用户级专用代理已设为 18484；完整退出并重开后生效。落地不可用时连接失败。'
