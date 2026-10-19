$ErrorActionPreference='Stop'
$runtime=Join-Path $env:USERPROFILE '.ssh\GermanyRouter'
$desktop=[Environment]::GetFolderPath('Desktop')
$stamp=Get-Date -Format 'yyyyMMdd-HHmmssfff'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
function Backup-One($path) {if(Test-Path -LiteralPath $path){Copy-Item -LiteralPath $path -Destination ($path+'.bak-'+$stamp)}}
foreach($name in @('App-Landing.Common.ps1','Configure-Claude-Landing.ps1','Configure-Edge-Landing.ps1','Edge-Policy.Common.ps1','Start-Claude-Landing.ps1','Start-Claude-Code-Landing.ps1','Test-Claude-Landing.ps1')) {
    $target=Join-Path $runtime $name
    Backup-One $target
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $target -Force
}
$shell=New-Object -ComObject WScript.Shell
$package=Get-AppxPackage -Name 'Claude' | Sort-Object Version -Descending | Select-Object -First 1
$claudeIcon=if($package){(Join-Path $package.InstallLocation 'app\Claude.exe')+',0'}else{'shell32.dll,0'}
$entries=@(
    @{label='Claude 客户端（落地）';script='Start-Claude-Landing.ps1';icon=$claudeIcon}
)
foreach($entry in $entries) {
    $target=Join-Path $desktop ($entry.label+'.lnk');Backup-One $target
    $link=$shell.CreateShortcut($target)
    $link.TargetPath=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $runtime $entry.script)+'"'
    $link.WorkingDirectory=$runtime;$link.IconLocation=$entry.icon;$link.Description='固定走落地入口 18484；落地不可用时连接失败。';$link.Save()
}
# Retain old entry points, but correct their meaning to the desktop client.
foreach($entry in @(@{alias='Claude-落地代理';script='Start-Claude-Landing.ps1'},@{alias='Claude-Code-落地代理';script='Start-Claude-Code-Landing.ps1'})) {
    $target=Join-Path $desktop ($entry.alias+'.ps1');Backup-One $target
    $content='& (Join-Path $env:USERPROFILE ''.ssh\GermanyRouter\'+$entry.script+''') @args'
    [IO.File]::WriteAllText($target,$content,[Text.UTF8Encoding]::new($true))
    $cmd=Join-Path $desktop ($entry.alias+'.cmd');Backup-One $cmd
    $content='@echo off'+"`r`n"+'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0'+$entry.alias+'.ps1" %*'+"`r`n"
    [IO.File]::WriteAllText($cmd,$content,[Text.Encoding]::GetEncoding(936))
}
$legacy=Join-Path $desktop 'Claude-Germany.vbs'
if(Test-Path $legacy) {
    Backup-One $legacy
    $vbs='Set s = CreateObject("WScript.Shell")'+"`r`n"+'s.Run "powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File """ & s.ExpandEnvironmentStrings("%USERPROFILE%") & "\.ssh\GermanyRouter\Start-Claude-Landing.ps1""", 0, False'
    [IO.File]::WriteAllText($legacy,$vbs,[Text.Encoding]::ASCII)
}
# Retire only our old dedicated Edge entry points. Preserve user browser data.
$retired=Join-Path $runtime ('retired-edge-launchers\'+$stamp)
$oldNames=@('Edge 浏览器（落地）.lnk','Edge-落地代理.ps1','Edge-落地代理.cmd')
$old=@(Get-ChildItem -LiteralPath $desktop -File | Where-Object {
    $name=$_.Name
    @($oldNames | Where-Object {$name -eq $_ -or $name.StartsWith($_+'.bak-')}).Count -gt 0
})
$old+=@(Get-Item -LiteralPath (Join-Path $runtime 'Start-Edge-Landing.ps1') -ErrorAction SilentlyContinue)
foreach($file in $old){
    $resolved=$file.FullName
    if((Split-Path $resolved -Parent) -notin @($desktop,$runtime)){throw '旧入口路径不在已核对的目录中。'}
    New-Item -ItemType Directory -Path $retired -Force | Out-Null
    Move-Item -LiteralPath $resolved -Destination (Join-Path $retired $file.Name)
}
Write-Output 'Claude 启动器已更新；Edge 专用入口已移入备份。日常 Edge 改由配置器开关管理。'
