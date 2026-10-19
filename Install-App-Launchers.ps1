$ErrorActionPreference='Stop'
$runtime=Join-Path $env:USERPROFILE '.ssh\GermanyRouter'
$desktop=[Environment]::GetFolderPath('Desktop')
$stamp=Get-Date -Format 'yyyyMMdd-HHmmssfff'
New-Item -ItemType Directory -Path $runtime -Force | Out-Null
function Backup-One($path) {if(Test-Path -LiteralPath $path){Copy-Item -LiteralPath $path -Destination ($path+'.bak-'+$stamp)}}
foreach($name in @('App-Landing.Common.ps1','Configure-Claude-Landing.ps1','Start-Claude-Landing.ps1','Start-Claude-Code-Landing.ps1','Start-Edge-Landing.ps1','Test-Claude-Landing.ps1')) {
    $target=Join-Path $runtime $name
    Backup-One $target
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $target -Force
}
$shell=New-Object -ComObject WScript.Shell
$package=Get-AppxPackage -Name 'Claude' | Sort-Object Version -Descending | Select-Object -First 1
$claudeIcon=if($package){(Join-Path $package.InstallLocation 'app\Claude.exe')+',0'}else{'shell32.dll,0'}
$entries=@(
    @{label='Claude 客户端（落地）';script='Start-Claude-Landing.ps1';icon=$claudeIcon},
    @{label='Edge 浏览器（落地）';script='Start-Edge-Landing.ps1';icon=((Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')+',0')}
)
foreach($entry in $entries) {
    $target=Join-Path $desktop ($entry.label+'.lnk');Backup-One $target
    $link=$shell.CreateShortcut($target)
    $link.TargetPath=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $link.Arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $runtime $entry.script)+'"'
    $link.WorkingDirectory=$runtime;$link.IconLocation=$entry.icon;$link.Description='固定走落地入口 18484；落地不可用时连接失败。';$link.Save()
}
# Retain old entry points, but correct their meaning to the desktop client.
foreach($entry in @(@{alias='Claude-落地代理';script='Start-Claude-Landing.ps1'},@{alias='Edge-落地代理';script='Start-Edge-Landing.ps1'},@{alias='Claude-Code-落地代理';script='Start-Claude-Code-Landing.ps1'})) {
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
Write-Output '已安装 Claude 客户端 / Edge 落地快捷方式，旧 Claude 命令行入口已改名为 Claude-Code-落地代理。'
