"""Exercise both landing exits on isolated ports; never mutate the live route."""
import argparse
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import shutil
import time
import urllib.request
import winreg
import sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
import yaml

REPO = Path(__file__).resolve().parents[1]
LIVE = Path.home() / '.ssh' / 'GermanyRouter'
CORE = Path(r'D:\Software\Clash Verge\verge-mihomo.exe')
PORT, CONTROL, SOCKS, TRANSPORT = 18684, 19690, 18683, 18682
FLAGS = subprocess.CREATE_NO_WINDOW

def run(args, timeout=90):
    return subprocess.run(args, capture_output=True, text=True, encoding=("gbk" if Path(str(args[0])).name.lower() == "powershell.exe" else "utf-8"), errors="replace", timeout=timeout,
                          creationflags=FLAGS, stdin=subprocess.DEVNULL)

def ps(script, *args):
    return run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
                '-File', str(REPO / script), *map(str, args)])

def listening(port):
    with socket.socket() as sock:
        sock.settimeout(.2)
        return sock.connect_ex(('127.0.0.1', port)) == 0

def live_snapshot():
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER,
                       r'Software\Microsoft\Windows\CurrentVersion\Internet Settings') as key:
        settings = {name: winreg.QueryValueEx(key, name)[0]
                    for name in ['ProxyEnable','ProxyServer','ProxyOverride']}
    settings['mode'] = (LIVE / 'mode.txt').read_text().strip()
    settings['upstream'] = (LIVE / 'upstream-choice.txt').read_text().strip()
    result = run(['powershell.exe','-NoProfile','-Command',
        'Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | '
        'Where-Object LocalPort -in 7980,18484,19090 | Sort-Object LocalPort | '
        'Select-Object LocalAddress,LocalPort,OwningProcess | ConvertTo-Json -Compress'])
    settings['listeners'] = json.loads(result.stdout)
    return settings

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', required=True)
    args = parser.parse_args()
    report = {'ports': [PORT, CONTROL, SOCKS, TRANSPORT]}
    before = live_snapshot()
    for port in [PORT, CONTROL, SOCKS, TRANSPORT]:
        assert not listening(port), f'Isolated port {port} is already occupied'
    directory = Path(tempfile.mkdtemp(prefix='landing-test-', dir=LIVE))
    isolated_core = directory / 'landing-router-core.exe'
    shutil.copy2(CORE, isolated_core)
    secret = (LIVE / 'controller-secret.txt').read_text().strip()
    (directory / 'controller-secret.txt').write_text(secret)
    (directory / 'mode.txt').write_text('apps')
    (directory / 'upstream-choice.txt').write_text('clash')
    (directory / 'landing-choice.txt').write_text('germany')
    endpoint = (LIVE / 'clash-upstream.txt').read_text().strip()
    config = yaml.safe_load((LIVE / 'config-global.yaml').read_text(encoding='utf-8-sig'))
    config.pop('proxy-providers', None)
    config['proxies'] = [p for p in config['proxies']
                         if p['name'] in {'Clash-Upstream','Wanda-Upstream','Germany-VLESS','NAS04-SSH'}]
    config['proxy-groups'] = [
        {'name':'FIRST-HOP','type':'select','proxies':['Clash-Upstream','Wanda-Upstream']},
        {'name':'GERMANY','type':'select','proxies':['Germany-VLESS']}]
    config['rules'] = ['MATCH,GERMANY']
    config['geodata-mode'] = False
    config['geo-auto-update'] = False
    config['profile'] = {'store-selected': False}
    for mode in ['foreign','global']:
        (directory / f'config-{mode}.yaml').write_text(yaml.safe_dump(config, sort_keys=False))
    process = None
    log_handle = (directory/'core-test.log').open('w', encoding='utf-8')
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    def api(path, method='GET', data=None):
        body = json.dumps(data).encode() if data is not None else None
        req = urllib.request.Request(f'http://127.0.0.1:{CONTROL}'+path,
            data=body, method=method,
            headers={'Authorization':'Bearer '+secret,'Content-Type':'application/json'})
        with opener.open(req, timeout=10) as response:
            raw = response.read()
        return json.loads(raw) if raw else None
    def select(choice):
        return ps('Set-Landing-Exit.ps1','-Choice',choice,'-RouterDir',directory,
                  '-ProxyPort',PORT,'-ControllerPort',CONTROL,
                  '-SocksPort',SOCKS,'-TransportPort',TRANSPORT)
    def exit_ip():
        result = run(['curl.exe','-fsS','--max-time','15','--noproxy','',
                      '--proxy',f'http://127.0.0.1:{PORT}','https://api.ipify.org'])
        assert result.returncode == 0, 'Isolated proxy request failed: '+str(result.returncode)+' '+result.stderr[-700:]
        return result.stdout.strip()
    try:
        for _ in range(2):
            result = ps('Ensure-Clash-Upstream.ps1','-Endpoint',endpoint,'-RouterDir',directory)
            assert result.returncode == 0, result.stderr
        config = yaml.safe_load((directory / 'config-foreign.yaml').read_text(encoding='utf-8-sig'))
        groups = {g['name']:g for g in config['proxy-groups']}
        assert len(groups) == len(config['proxy-groups'])
        assert groups['LANDING']['proxies'] == ['Germany-VLESS','NAS04-SSH']
        assert groups['GERMANY']['proxies'] == ['LANDING']
        assert 'NAS04-SSH' not in groups['FIRST-HOP']['proxies']
        assert len(config['tunnels']) == 1
        config['mixed-port'] = PORT
        config['external-controller'] = f'127.0.0.1:{CONTROL}'
        config['tunnels'] = [f'tcp,127.0.0.1:{TRANSPORT},212.121.132.230:22,FIRST-HOP']
        next(p for p in config['proxies'] if p['name']=='NAS04-SSH')['port'] = SOCKS
        path = directory / 'config-foreign.yaml'
        path.write_text(yaml.safe_dump(config,sort_keys=False))
        checked = run([str(isolated_core),'-t','-d',str(directory),'-f',str(path)])
        assert checked.returncode == 0, 'Mihomo rejected isolated configuration'
        report['config_idempotent_and_valid'] = True
        process = subprocess.Popen([str(isolated_core),'-d',str(directory),'-f',str(path)],
            stdout=log_handle, stderr=log_handle, creationflags=FLAGS)
        for _ in range(50):
            if listening(PORT) and listening(CONTROL): break
            time.sleep(.2)
        assert listening(PORT)
        original_rules = config['rules']
        config['rules'] = ['MATCH,FIRST-HOP']
        path.write_text(yaml.safe_dump(config,sort_keys=False))
        api('/configs?force=true','PUT',{'path':str(path)})
        report['first_hop_exit'] = exit_ip()
        print('First-hop HTTP forwarding passed', flush=True)
        config['rules'] = original_rules
        path.write_text(yaml.safe_dump(config,sort_keys=False))
        api('/configs?force=true','PUT',{'path':str(path)})
        result = select('germany')
        
        if result.returncode != 0:
            probe=run(['curl.exe','-v','--max-time','15','--proxy',f'http://127.0.0.1:{PORT}','https://api.ipify.org'])
            report['germany_probe']={'code':probe.returncode,'stdout':probe.stdout,'stderr':probe.stderr[-2500:]}
            report['group_state']={name:api('/proxies/'+name).get('now') for name in ['LANDING','FIRST-HOP','GERMANY']}
        assert result.returncode == 0, result.stderr
        report['germany_exit'] = exit_ip()
        assert report['germany_exit'] in {'192.248.188.234','2a05:f480:1800:2d04:5400:5ff:fe92:1848'}
        print('Original landing exit passed',flush=True)
        result = select('nas04')
        assert result.returncode == 0, result.stderr
        report['nas04_exit'] = exit_ip()
        assert report['nas04_exit'] == '212.121.132.230'
        chains = [c['chains'] for c in api('/connections')['connections']
                  if c['metadata'].get('destinationIP') == '212.121.132.230'
                  and str(c['metadata'].get('destinationPort')) == '22']
        assert any('Clash-Upstream' in chain for chain in chains), 'SSH transport bypassed selected upstream'
        report['nas04_ssh_transport_chains'] = chains
        result = run(['curl.exe','-sS','--max-time','15','--noproxy','', '--proxy',
                      f'http://127.0.0.1:{PORT}','-o','NUL','-w','%{http_code}',
                      'https://www.youtube.com/generate_204'])
        assert result.returncode == 0 and result.stdout.strip() == '204'
        report['nas04_youtube_status'] = 204
        print('NAS04 final exit via Clash passed',flush=True)
        result = select('germany')
        assert result.returncode == 0, result.stderr
        assert exit_ip() == report['germany_exit']
        assert not listening(SOCKS), 'SSH SOCKS listener leaked after switching away'
        report['switch_back_and_tunnel_cleanup'] = True
        # Break only the isolated upstream. There must be no direct SSH fallback.
        next(p for p in config['proxies'] if p['name']=='Clash-Upstream')['port'] = 9
        path.write_text(yaml.safe_dump(config,sort_keys=False))
        api('/configs?force=true','PUT',{'path':str(path)})
        result = select('nas04')
        assert result.returncode != 0
        assert api('/proxies/LANDING')['now'] == 'Germany-VLESS'
        assert (directory/'landing-choice.txt').read_text().strip() == 'germany'
        assert not listening(SOCKS)
        report['upstream_unavailable_fails_without_direct_fallback'] = True
        report['failed_switch_preserves_previous_choice'] = True
        print('Unavailable-upstream and rollback checks passed',flush=True)
        (directory/'mode.txt').write_text('off')
        result = select('nas04')
        assert result.returncode == 0
        assert not listening(SOCKS)
        assert (directory/'landing-choice.txt').read_text().strip() == 'nas04'
        report['off_mode_only_saves_selection'] = True
        report['passed'] = True
    except Exception as exc:
        report['passed'] = False
        report['error'] = str(exc)
        log_handle.flush()
        log=(directory/'core-test.log').read_text(encoding='utf-8',errors='replace')
        def scrub(obj):
            nonlocal log
            if isinstance(obj,dict):
                for k,v in obj.items():
                    if k in {'uuid','password','secret','path'} and isinstance(v,str): log=log.replace(v,'[redacted]')
                    else: scrub(v)
            elif isinstance(obj,list):
                for item in obj: scrub(item)
        scrub(config)
        report['diagnostic_log']=log[-3000:]
    finally:
        ps('Stop-NAS04-Socks.ps1','-RouterDir',directory)
        if process:
            process.terminate()
            process.wait(timeout=10)
        log_handle.close()
        report['production_unchanged'] = live_snapshot() == before
        report['isolated_ports_closed'] = not any(listening(p) for p in [PORT,CONTROL,SOCKS,TRANSPORT])
        report['passed'] = bool(report.get('passed') and report['production_unchanged'] and report['isolated_ports_closed'])
        Path(args.report).write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
        print(json.dumps(report,indent=2,ensure_ascii=False),flush=True)
        # Credential-bearing temporary files stay in .ssh, never in the repo/report.
        for file in directory.iterdir():
            if file.is_file(): file.unlink()
        directory.rmdir()
    return 0 if report['passed'] else 1

if __name__ == '__main__':
    raise SystemExit(main())
