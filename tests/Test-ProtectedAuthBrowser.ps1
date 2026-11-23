$ErrorActionPreference='Stop'
$file=Join-Path $env:USERPROFILE '.ssh\GermanyRouter\StrictGermany\ProtectedAuthBrowser.exe'
$assembly=[Reflection.Assembly]::LoadFile($file)
$method=$assembly.GetType('ProtectedAuthBrowser').GetMethod('Prepare',[Reflection.BindingFlags]'Static,NonPublic')
$inputUrl='https://claude.ai/oauth/authorize?redirect_uri=http%3A%2F%2Flocalhost%3A54321%2Fcallback&state=synthetic-test&code_challenge=synthetic-challenge&scope=user%3Aprofile'
$result=$method.Invoke($null,@($inputUrl))
Add-Type -AssemblyName System.Web
$q=[Web.HttpUtility]::ParseQueryString(([uri]$result).Query)
if($q['redirect_uri'] -ne 'https://platform.claude.com/oauth/code/callback' -or $q['state'] -ne 'synthetic-test' -or $q['code_challenge'] -ne 'synthetic-challenge' -or $q['scope'] -ne 'user:profile'){throw 'Manual redirect transformation corrupted login parameters'}
foreach($url in @('http://claude.ai/oauth/authorize','https://claude.ai.attacker.invalid/','https://user@claude.ai/','file:///C:/test','https://claude.ai:444/','https://claude.ai/oauth/authorize?redirect_uri=http%3A%2F%2Flocalhost%3A54321%2Funknown')) {
    $blocked=$false;try{$null=$method.Invoke($null,@($url))}catch{$blocked=$true}
    if(-not $blocked){throw 'Unsafe input accepted'}
}
Write-Output 'PASS: manual OAuth redirect preserves state/challenge; invalid URLs rejected; no browser/login request made.'
