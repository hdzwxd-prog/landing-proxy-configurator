"""Offline orchestration tests: no real proxy, application, registry or network access."""
import subprocess, tempfile, unittest, shutil
from pathlib import Path
REPO=Path(__file__).resolve().parents[1]

class IntegratedRouteTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='route-unit-')
        self.root=Path(self.temp.name)
        self.strict=self.root/'StrictGermany';self.strict.mkdir()
        for name,value in {'mode.txt':'apps','upstream-choice.txt':'clash','clash-upstream.txt':'127.0.0.1:7980','landing-choice.txt':'nas04'}.items():
            (self.root/name).write_text(value)
        for name,value in {'isolation-install.json':'{}','config.json':'original-secret-fixture','upstream-choice.txt':'wanda','enabled.txt':'true'}.items():
            (self.strict/name).write_text(value)
        self.write(self.root/'Set-Germany-Upstream.ps1',r'''
param($Choice,$Endpoint,$Landing,$RouterDir)
$ErrorActionPreference='Stop'
Add-Content (Join-Path $PSScriptRoot 'calls.txt') "normal:$Choice/$Landing"
if(Test-Path (Join-Path $PSScriptRoot 'normal-fail')){throw 'normal unavailable'}
Set-Content (Join-Path $RouterDir 'upstream-choice.txt') $Choice
Set-Content (Join-Path $RouterDir 'clash-upstream.txt') $Endpoint
Set-Content (Join-Path $RouterDir 'landing-choice.txt') $Landing
''')
        self.write(self.strict/'Set-StrictUpstream.ps1',r'''
param($Choice,$Endpoint,[switch]$Stop)
$ErrorActionPreference='Stop'
Add-Content (Join-Path (Split-Path $PSScriptRoot) 'calls.txt') "strict:$Choice/stop=$Stop"
if($Stop){Set-Content (Join-Path $PSScriptRoot 'enabled.txt') 'false';exit 0}
Set-Content (Join-Path $PSScriptRoot 'config.json') 'changed'
Set-Content (Join-Path $PSScriptRoot 'upstream-choice.txt') $Choice
if(Test-Path (Join-Path $PSScriptRoot 'fail')){throw 'strict unavailable'}
''')
        self.write(self.strict/'Start-StrictGermany.ps1',r'''
$ErrorActionPreference='Stop'
Add-Content (Join-Path (Split-Path $PSScriptRoot) 'calls.txt') 'restore-strict'
if(Test-Path (Join-Path $PSScriptRoot 'restore-fail')){throw 'restore unavailable'}
''')
    def tearDown(self): self.temp.cleanup()
    def write(self,path,text):path.write_text(text,encoding='utf-8-sig')
    def run_route(self,choice='wanda',endpoint='127.0.0.1:7980'):
        return subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(REPO/'Set-IntegratedRoute.ps1'),'-Choice',choice,'-Landing','germany','-Endpoint',endpoint,'-RouterDir',str(self.root)],capture_output=True,timeout=20,creationflags=subprocess.CREATE_NO_WINDOW)
    def read(self,path):return path.read_text(encoding='utf-8-sig').strip()
    def test_joint_choice_success(self):
        r=self.run_route();self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.read(self.root/'landing-choice.txt'),'germany')
        self.assertEqual(self.read(self.root/'upstream-choice.txt'),'wanda')
        self.assertEqual(self.read(self.strict/'upstream-choice.txt'),'wanda')
        self.assertEqual(self.read(self.root/'calls.txt').splitlines(),['normal:wanda/germany','strict:wanda/stop=False'])
    def test_strict_failure_restores_mixed_previous_state(self):
        (self.strict/'fail').touch();r=self.run_route();self.assertNotEqual(r.returncode,0)
        self.assertEqual(self.read(self.root/'upstream-choice.txt'),'clash')
        self.assertEqual(self.read(self.root/'landing-choice.txt'),'nas04')
        self.assertEqual(self.read(self.strict/'config.json'),'original-secret-fixture')
        self.assertEqual(self.read(self.strict/'upstream-choice.txt'),'wanda')
        self.assertIn('restore-strict',self.read(self.root/'calls.txt'))
    def test_rollback_failure_does_not_claim_restored(self):
        (self.strict/'fail').touch();(self.strict/'restore-fail').touch()
        r=self.run_route();self.assertNotEqual(r.returncode,0)
        self.assertEqual(self.read(self.root/'upstream-choice.txt'),'clash')
        self.assertEqual(self.read(self.root/'landing-choice.txt'),'nas04')
        # Verify the structured failure branch actually reaches the caller.
        self.assertTrue(r.stderr)
    def test_normal_failure_does_not_touch_strict(self):
        (self.root/'normal-fail').touch();r=self.run_route();self.assertNotEqual(r.returncode,0)
        self.assertNotIn('strict:',self.read(self.root/'calls.txt'))
        self.assertEqual(self.read(self.strict/'config.json'),'original-secret-fixture')
    def test_off_never_starts_services(self):
        (self.root/'mode.txt').write_text('off');r=self.run_route();self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.root/'calls.txt').exists())
    def test_recursive_endpoint_rejected_before_mutation(self):
        r=self.run_route('clash','127.0.0.1:18485');self.assertNotEqual(r.returncode,0)
        self.assertFalse((self.root/'calls.txt').exists())
    def test_uninstalled_strict_only_updates_regular_route(self):
        (self.strict/'isolation-install.json').unlink();r=self.run_route();self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.read(self.root/'calls.txt'),'normal:wanda/germany')


class JointNormalRouteTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='normal-route-unit-');self.root=Path(self.temp.name)
        shutil.copy2(REPO/'Set-Germany-Upstream.ps1',self.root/'Set-Germany-Upstream.ps1')
        for name,value in {'mode.txt':'apps','landing-choice.txt':'nas04','upstream-choice.txt':'clash','clash-upstream.txt':'127.0.0.1:7980','actual-first':'Clash-Upstream','actual-landing':'NAS04-SSH'}.items():
            (self.root/name).write_text(value)
        (self.root/'Landing.Common.ps1').write_text(r"""
function Enter-LandingChange($mutex,$timeout){return $mutex.WaitOne($timeout)}
function Get-UpstreamChoice{return (Get-Content (Join-Path $routerDir 'upstream-choice.txt') -Raw).Trim()}
function Get-LandingChoice{return (Get-Content (Join-Path $routerDir 'landing-choice.txt') -Raw).Trim()}
function Get-UpstreamTarget($choice){if($choice -eq 'wanda'){return 'Wanda-Upstream'};return 'Clash-Upstream'}
function Get-LandingTarget($choice){if($choice -eq 'nas04'){return 'NAS04-SSH'};return 'Germany-VLESS'}
function Test-LandingListener($port){return $true}
function Ensure-LandingRuntime{}
function Write-LandingHealth($choice,$state,$detail){}
function Stop-Nas04Socks{}
function Ensure-Nas04Socks($s,$t){}
function Set-LandingGroup($group,$target){
    $file=if($group -eq 'FIRST-HOP'){'actual-first'}else{'actual-landing'}
    Set-Content (Join-Path $routerDir $file) $target
}
function Test-LandingExit($choice,$port){
    $first=(Get-Content (Join-Path $routerDir 'actual-first') -Raw).Trim()
    $exit=(Get-Content (Join-Path $routerDir 'actual-landing') -Raw).Trim()
    Add-Content (Join-Path $routerDir 'verified') "$first/$exit"
    if($first -eq 'Wanda-Upstream' -and (Test-Path (Join-Path $routerDir 'reject-new'))){return $false}
    # Both diagonal combinations work, intermediate combinations fail.
    return ($first -eq 'Wanda-Upstream' -and $exit -eq 'Germany-VLESS') -or ($first -eq 'Clash-Upstream' -and $exit -eq 'NAS04-SSH')
}
""",encoding='utf-8-sig')
    def tearDown(self):self.temp.cleanup()
    def run_route(self):
        return subprocess.run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(self.root/'Set-Germany-Upstream.ps1'),'-Choice','wanda','-Landing','germany','-RouterDir',str(self.root)],capture_output=True,timeout=20,creationflags=subprocess.CREATE_NO_WINDOW)
    def read(self,name):return (self.root/name).read_text(encoding='utf-8-sig').strip()
    def test_only_final_combination_is_validated(self):
        r=self.run_route();self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.read('verified'),'Wanda-Upstream/Germany-VLESS')
        self.assertEqual(self.read('upstream-choice.txt'),'wanda');self.assertEqual(self.read('landing-choice.txt'),'germany')
    def test_both_selections_restored_on_failed_exit(self):
        (self.root/'reject-new').touch();r=self.run_route();self.assertNotEqual(r.returncode,0)
        self.assertEqual(self.read('upstream-choice.txt'),'clash');self.assertEqual(self.read('landing-choice.txt'),'nas04')
        self.assertEqual(self.read('actual-first'),'Clash-Upstream');self.assertEqual(self.read('actual-landing'),'NAS04-SSH')
        self.assertEqual(self.read('verified').splitlines()[-1],'Clash-Upstream/NAS04-SSH')
    def test_off_saves_both_without_touching_runtime(self):
        (self.root/'mode.txt').write_text('off');r=self.run_route();self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(self.read('upstream-choice.txt'),'wanda');self.assertEqual(self.read('landing-choice.txt'),'germany')
        self.assertEqual(self.read('actual-first'),'Clash-Upstream');self.assertFalse((self.root/'verified').exists())

if __name__=='__main__':unittest.main()

