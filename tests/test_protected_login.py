"""No account or production process: exercise actual launcher with a fake CLI."""
import hashlib,json,os,shutil,subprocess,tempfile,unittest
from pathlib import Path
REPO=Path(__file__).resolve().parents[1]
CSC=Path(os.environ['WINDIR'])/'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
def run(args,**kw):
    return subprocess.run(args,capture_output=True,text=True,creationflags=subprocess.CREATE_NO_WINDOW,timeout=40,**kw)
class LoginBoundary(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory();self.home=Path(self.tmp.name)
        self.root=self.home/'.ssh/GermanyRouter/StrictGermany';self.root.mkdir(parents=True)
        self.local=self.home/'local';self.app=self.home/'roaming'
        self.exe=self.app/'npm/node_modules/@anthropic-ai/claude-code/bin/claude.exe';self.exe.parent.mkdir(parents=True)
        code=self.home/'stub.cs'
        code.write_text('using System;using System.Web.Script.Serialization;class P{static void Main(string[] a){Console.WriteLine("STUB="+new JavaScriptSerializer().Serialize(new {args=a,proxy=Environment.GetEnvironmentVariable("HTTPS_PROXY"),browser=Environment.GetEnvironmentVariable("BROWSER")}));}}')
        r=run([str(CSC),'/nologo','/r:System.Web.Extensions.dll','/out:'+str(self.exe),str(code)]);assert r.returncode==0,r.stdout+r.stderr
        self.receipt={'ok':True,'exe':str(self.exe),'hash':hashlib.sha256(self.exe.read_bytes()).hexdigest().upper()}
        (self.root/'cli-isolation.json').write_text(json.dumps(self.receipt))
        shutil.copy(REPO/'strict/Invoke-ProtectedClaude.ps1',self.root)
        self.policy=self.local/'Programs/Mozilla Firefox/distribution/policies.json';self.policy.parent.mkdir(parents=True)
        shutil.copy(REPO/'strict/firefox-policies.json',self.policy)
        (self.root/'ProtectedAuthBrowser.exe').touch()
        (self.root/'Start-StrictGermany.ps1').write_text("param([switch]$CheckOnly)\nif(-not $CheckOnly){throw 'Must not start core'}")
        self.env=dict(os.environ,USERPROFILE=str(self.home),APPDATA=str(self.app),LOCALAPPDATA=str(self.local),HTTPS_PROXY='http://127.0.0.1:7892',BROWSER='unsafe-default')
    def tearDown(self):self.tmp.cleanup()
    def invoke(self,*args):return run(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass','-File',str(self.root/'Invoke-ProtectedClaude.ps1'),*args],env=self.env)
    def test_login_pins_proxy_browser_and_preserves_arguments(self):
        r=self.invoke('auth','login','--email','test@example.invalid');self.assertEqual(r.returncode,0,r.stdout+r.stderr)
        data=json.loads(next(s[5:] for s in r.stdout.splitlines() if s.startswith('STUB=')))
        self.assertEqual(data['args'],['auth','login','--email','test@example.invalid'])
        self.assertEqual(data['proxy'],'http://127.0.0.1:18485')
        self.assertEqual(data['browser'],str(self.root/'ProtectedAuthBrowser.exe'))
        self.assertEqual(self.env['HTTPS_PROXY'],'http://127.0.0.1:7892')
    def test_failed_exit_never_starts_cli(self):
        (self.root/'Start-StrictGermany.ps1').write_text("throw 'Germany unreachable'")
        r=self.invoke('auth','login');self.assertNotEqual(r.returncode,0);self.assertNotIn('STUB=',r.stdout)
    def test_changed_cli_never_starts(self):
        self.receipt['hash']='bad';(self.root/'cli-isolation.json').write_text(json.dumps(self.receipt))
        r=self.invoke('auth','login');self.assertNotEqual(r.returncode,0);self.assertNotIn('STUB=',r.stdout)
    def test_unlocked_firefox_never_starts_cli(self):
        p=json.loads(self.policy.read_text());p['policies']['Proxy']['Locked']=False;self.policy.write_text(json.dumps(p))
        r=self.invoke('auth','login');self.assertNotEqual(r.returncode,0);self.assertNotIn('STUB=',r.stdout)
if __name__=='__main__':unittest.main()
