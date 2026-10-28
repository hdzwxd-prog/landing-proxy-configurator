"""Real route switching/reconnect tests on isolated ports, with production invariants."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import urllib.request
import winreg
import yaml
from test_landing import run, ps, listening, REPO, LIVE

PORT, CONTROL, SOCKS, TRANSPORT = 18684, 19690, 18683, 18682
FLAGS = subprocess.CREATE_NO_WINDOW

def snapshot():
    result = {}
    for name, keypath, values in [
        ('system', r'Software\Microsoft\Windows\CurrentVersion\Internet Settings',
         ['ProxyEnable', 'ProxyServer', 'ProxyOverride', 'AutoConfigURL']),
        ('edge', r'Software\Policies\Microsoft\Edge',
         ['ProxySettings','QuicAllowed','WebRtcLocalhostIpHandling']),
    ]:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, keypath) as key:
            result[name] = {}
            for value in values:
                try: result[name][value] = winreg.QueryValueEx(key, value)
                except FileNotFoundError: result[name][value] = None
    files = list((Path(os.environ['LOCALAPPDATA'])/'Claude-3p'/'configLibrary').glob('*.json'))
    files += [LIVE/name for name in ['mode.txt','landing-choice.txt','upstream-choice.txt',
                                     'clash-upstream.txt','config-global.yaml','config-foreign.yaml']]
    result['files'] = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    proc = run(['powershell.exe','-NoProfile','-Command',
        'Get-NetTCPConnection -State Listen | Where-Object LocalPort -in 7892,7980,18484,19090 | '
        'Sort-Object LocalPort | Select-Object LocalAddress,LocalPort,OwningProcess | ConvertTo-Json -Compress'])
    result['listeners'] = json.loads(proc.stdout)
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    before = snapshot()
    report = {'steps': [], 'ports': [PORT, CONTROL, SOCKS, TRANSPORT]}
    for port in report['ports']:
        assert not listening(port), f'Test port occupied: {port}'
    directory = Path(tempfile.mkdtemp(prefix='upstream-test-', dir=LIVE))
    core = directory/'landing-router-core.exe'
    shutil.copy2(LIVE/'landing-router-core.exe', core)
    shutil.copy2(REPO/'Landing.Common.ps1', directory/'Landing.Common.ps1')
    secret = (LIVE/'controller-secret.txt').read_text().strip()
    (directory/'controller-secret.txt').write_text(secret)
    endpoint = (LIVE/'clash-upstream.txt').read_text().strip()
    for name, value in [('mode.txt','apps'),('landing-choice.txt','germany'),
                        ('upstream-choice.txt','clash'),('clash-upstream.txt',endpoint)]:
        (directory/name).write_text(value)
    config = yaml.safe_load((LIVE/'config-global.yaml').read_text(encoding='utf-8-sig'))
    config['mixed-port'] = PORT
    config['external-controller'] = f'127.0.0.1:{CONTROL}'
    config.pop('proxy-providers', None)
    config['profile'] = {'store-selected': False}
    config['geodata-mode'] = False
    config['geo-auto-update'] = False
    config['dns'] = {'enable': False}
    config['tun'] = {'enable': False}
    config['tunnels'] = [f'tcp,127.0.0.1:{TRANSPORT},212.121.132.230:22,FIRST-HOP']
    next(p for p in config['proxies'] if p['name']=='NAS04-SSH')['port'] = SOCKS
    config['proxy-groups'] = [
        {'name':'FIRST-HOP','type':'select','proxies':['Clash-Upstream','Wanda-Upstream']},
        {'name':'LANDING','type':'select','proxies':['Germany-VLESS','NAS04-SSH']}]
    config['rules'] = ['MATCH,LANDING']
    for mode in ['foreign','global']:
        (directory/f'config-{mode}.yaml').write_text(yaml.safe_dump(config, sort_keys=False))
    options = ['-RouterDir',directory,'-ProxyPort',PORT,'-ControllerPort',CONTROL,
               '-SocksPort',SOCKS,'-TransportPort',TRANSPORT]
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def api(path, method='GET', data=None):
        req = urllib.request.Request(f'http://127.0.0.1:{CONTROL}'+path,
            data=json.dumps(data).encode() if data is not None else None,
            method=method, headers={'Authorization':'Bearer '+secret,'Content-Type':'application/json'})
        with opener.open(req, timeout=10) as response: raw=response.read()
        return json.loads(raw) if raw else None
    def check(result):
        assert result.returncode == 0, result.stderr[-1400:]
    def switch(choice, new_endpoint=endpoint):
        return ps('Set-Germany-Upstream.ps1','-Choice',choice,'-Endpoint',new_endpoint,*options)
    def reconnect():
        return ps('Restart-Germany-Router.ps1',*options)
    def exit_ip():
        for url in ['https://api.ipify.org','https://ifconfig.me/ip']:
            started = time.monotonic()
            proc = run(['curl.exe','-q','-fsS','--noproxy','','--max-time','12',
                        '--proxy',f'http://127.0.0.1:{PORT}',url])
            report.setdefault('probes',[]).append({'url':url, 'code':proc.returncode,
                'seconds':round(time.monotonic()-started,2)})
            if proc.returncode == 0:
                return proc.stdout.strip()
        raise AssertionError('Both independent exit endpoints failed')
    def step(text):
        report['steps'].append(text)
        print(text, flush=True)
    supervisor = None
    process = None
    log = (directory/'test.log').open('w')
    try:
        checked = run([str(core),'-t','-d',str(directory),'-f',str(directory/'config-global.yaml')])
        assert checked.returncode == 0, 'Invalid isolated configuration'
        process = subprocess.Popen([str(core),'-d',str(directory),'-f',str(directory/'config-global.yaml')],
                                    stdout=log,stderr=log,creationflags=FLAGS)
        for _ in range(50):
            if listening(CONTROL): break
            time.sleep(.2)
        assert listening(CONTROL)
        original_pid = process.pid
        for choice in ['clash','wanda','clash','wanda']:
            check(switch(choice))
            assert api('/proxies/FIRST-HOP')['now'] == ('Clash-Upstream' if choice=='clash' else 'Wanda-Upstream')
            assert (directory/'upstream-choice.txt').read_text().strip() == choice
            assert exit_ip() == '192.248.188.234'
            check(reconnect())
            assert process.poll() is None and process.pid == original_pid
            step(f'{choice}: switch and reconnect verified; core PID preserved')
        # Invalid/closed endpoint must restore exact bytes and verify previous Wanda route.
        protected = ['config-global.yaml','config-foreign.yaml','upstream-choice.txt','clash-upstream.txt']
        saved = {name:(directory/name).read_bytes() for name in protected}
        for bad in [f'127.0.0.1:{PORT}', '127.0.0.1:9']:
            assert switch('clash',bad).returncode != 0, 'Bad endpoint was accepted'
            assert {name:(directory/name).read_bytes() for name in protected} == saved
            assert api('/proxies/FIRST-HOP')['now'] == 'Wanda-Upstream'
            assert exit_ip() == '192.248.188.234'
        step('Self-loop rejected; unreachable upstream rolls back files and live route')
        # Observe NAS04 compatibility separately: failure is valid only if rollback really works.
        nas = ps('Set-Landing-Exit.ps1','-Choice','nas04',*options)
        report['nas04_via_wanda_available'] = nas.returncode == 0
        if nas.returncode == 0:
            assert exit_ip() == '212.121.132.230'
            check(reconnect())
            assert exit_ip() == '212.121.132.230'
            check(ps('Set-Landing-Exit.ps1','-Choice','germany',*options))
            step('NAS04 via Wanda: exit and SSH reconnect verified')
        else:
            assert api('/proxies/LANDING')['now'] == 'Germany-VLESS'
            assert exit_ip() == '192.248.188.234'
            step('NAS04 via Wanda unavailable; Germany rollback verified')
        # Terminate only our isolated process to exercise supervisor recovery.
        process.terminate()
        process.wait(timeout=10)
        process = None
        (directory/'upstream-choice.txt').write_text('clash')
        check(ps('Ensure-Clash-Upstream.ps1','-Endpoint','127.0.0.1:9',
                 '-RouterDir',directory,'-ProxyPort',PORT,'-ControllerPort',CONTROL,
                 '-SocksPort',SOCKS,'-TransportPort',TRANSPORT))
        supervisor = subprocess.Popen(['powershell.exe','-NoProfile','-ExecutionPolicy','Bypass',
            '-File',str(REPO/'Start-Germany-Router.ps1'),*map(str,options),'-Isolated'],
            stdout=log,stderr=log,creationflags=FLAGS)
        for _ in range(90):
            if listening(CONTROL): break
            assert supervisor.poll() is None, 'Supervisor exited on absent upstream'
            time.sleep(.5)
        assert listening(CONTROL)
        time.sleep(20)
        assert supervisor.poll() is None, 'Supervisor exited instead of waiting for upstream'
        check(switch('clash'))
        assert exit_ip() == '192.248.188.234'
        step('Supervisor survives absent upstream and recovers when its endpoint returns')
        core_proc = run(['powershell.exe','-NoProfile','-Command',
            f'(Get-NetTCPConnection -LocalPort {CONTROL} -State Listen).OwningProcess'])
        recovered_pid = int(core_proc.stdout.strip())
        # Test-only owned executable PID, not an upstream/core in production.
        run(['powershell.exe','-NoProfile','-Command',f'Stop-Process -Id {recovered_pid}'])
        for _ in range(80):
            time.sleep(.5)
            if listening(CONTROL):
                try:
                    if api('/proxies/FIRST-HOP')['now']=='Clash-Upstream': break
                except Exception: pass
        assert listening(CONTROL) and supervisor.poll() is None
        assert exit_ip() == '192.248.188.234'
        step('Independent core crash recovered without restarting Wanda or Clash')
        (directory/'mode.txt').write_text('off')
        supervisor.wait(timeout=35)
        supervisor = None
        # Stop leaves the upstream clients and other apps entirely alone.
        selected = api('/proxies/FIRST-HOP')['now']
        check(switch('wanda'))
        assert api('/proxies/FIRST-HOP')['now'] == selected
        step('Off mode saves selection without changing runtime route')
        report['passed'] = True
    except Exception as exc:
        report['passed'] = False
        report['error'] = str(exc).replace(secret,'[redacted]')
    finally:
        if supervisor and supervisor.poll() is None:
            (directory/'mode.txt').write_text('off')
            try: supervisor.wait(timeout=35)
            except subprocess.TimeoutExpired: supervisor.terminate(); supervisor.wait(timeout=10)
        ps('Stop-NAS04-Socks.ps1','-RouterDir',directory)
        if process and process.poll() is None: process.terminate(); process.wait(timeout=10)
        # Only our test core's listener, guarded by executable path and test port.
        run(['powershell.exe','-NoProfile','-Command',
            f"$c=Get-NetTCPConnection -LocalPort {CONTROL} -State Listen -ErrorAction SilentlyContinue; "
            f"if($c){{$p=Get-Process -Id $c.OwningProcess; if($p.Path -eq '{core}'){{Stop-Process -Id $p.Id}}}}"])
        log.close()
        report['production_unchanged'] = snapshot() == before
        report['isolated_ports_closed'] = not any(listening(p) for p in report['ports'])
        report['passed'] = bool(report.get('passed') and report['production_unchanged'] and report['isolated_ports_closed'])
        Path(args.report).write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(report,ensure_ascii=False,indent=2),flush=True)
        # Credential-bearing files stay under .ssh; remove only this resolved test directory.
        assert directory.resolve().parent == LIVE.resolve() and directory.name.startswith('upstream-test-')
        shutil.rmtree(directory)
    return 0 if report['passed'] else 1

if __name__=='__main__':
    raise SystemExit(main())

