from __future__ import annotations
import pathlib, sys
import yaml
ROUTER = pathlib.Path.home() / '.ssh' / 'GermanyRouter'
SECRET_FILE = ROUTER / 'controller-secret.txt'
ENDPOINT_FILE = ROUTER / 'clash-upstream.txt'
def build(path: pathlib.Path) -> None:
    data = yaml.safe_load(path.read_text(encoding='utf-8-sig'))
    secret = SECRET_FILE.read_text(encoding='ascii').strip()
    endpoint = ENDPOINT_FILE.read_text(encoding='ascii').strip() if ENDPOINT_FILE.exists() else '127.0.0.1:7980'
    host, port_text = endpoint.rsplit(':', 1)
    data['external-controller'] = '127.0.0.1:19090'
    data['secret'] = secret
    data['find-process-mode'] = 'off'
    data.pop('proxy-providers', None)
    proxies = [p for p in data.get('proxies', []) if p.get('name') not in {'Clash-Upstream', 'BigAirport-SG', 'NAS04-SSH'}]
    proxies.insert(0, {'name':'Clash-Upstream','type':'http','server':host,'port':int(port_text),'udp':False})
    proxies.insert(1, {'name':'NAS04-SSH','type':'socks5','server':'127.0.0.1','port':18583,'udp':False})
    data['proxies'] = proxies
    germany = next(p for p in proxies if p.get('name') == 'Germany-VLESS')
    germany['dialer-proxy'] = 'FIRST-HOP'
    terminal_groups = [g for g in data.get('proxy-groups', []) if g.get('name') not in {'BigAirport-SG','FIRST-HOP','LANDING'}]
    for group in terminal_groups:
        group['proxies'] = ['LANDING' if name == 'Germany-VLESS' else name for name in group.get('proxies', [])]
    data['tunnels'] = ['tcp,127.0.0.1:18584,212.121.132.230:22,FIRST-HOP']
    terminal_groups.insert(0, {'name':'LANDING','type':'select','proxies':['Germany-VLESS','NAS04-SSH']})
    data['proxy-groups'] = [{'name':'FIRST-HOP','type':'select','proxies':['Clash-Upstream','Wanda-Upstream']}, *terminal_groups]
    path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False, width=4096), encoding='utf-8')
def main() -> int:
    if not SECRET_FILE.exists() or not SECRET_FILE.read_text(encoding='ascii').strip(): raise RuntimeError('controller secret is missing')
    for name in ('config-foreign.yaml','config-global.yaml'): build(ROUTER / name)
    return 0
if __name__ == '__main__': sys.exit(main())
