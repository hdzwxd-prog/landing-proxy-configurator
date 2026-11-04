"""Derive a private Germany-only config. Never print/store credentials in Git."""
import argparse, copy, json, pathlib
import yaml

def generate(source, endpoint):
    host, port = endpoint.rsplit(':', 1)
    port = int(port)
    if host != '127.0.0.1' or not 1 <= port <= 65535 or port in (18484,18485):
        raise ValueError('Upstream must be a separate local HTTP/mixed proxy')
    germany = copy.deepcopy(next(p for p in source['proxies'] if p['name'] == 'Germany-VLESS'))
    if germany['server'] != '192.248.188.234' or germany['port'] != 443:
        raise ValueError('Unexpected Germany destination; manual review required')
    germany['dialer-proxy'] = 'STRICT-UPSTREAM'
    return {'mixed-port':18485, 'bind-address':'127.0.0.1', 'allow-lan':False,
            'mode':'rule', 'log-level':'error', 'ipv6':False,
            'profile':{'store-selected':False}, 'dns':{'enable':False},
            'proxies':[{'name':'STRICT-UPSTREAM','type':'http','server':host,'port':port},germany],
            'rules':['MATCH,Germany-VLESS']}

if __name__ == '__main__':
    a=argparse.ArgumentParser();a.add_argument('--router',type=pathlib.Path,required=True)
    a.add_argument('--output',type=pathlib.Path,required=True);a.add_argument('--endpoint',required=True);x=a.parse_args()
    source=yaml.safe_load((x.router/'config-global.yaml').read_text(encoding='utf-8-sig'))
    config=generate(source,x.endpoint)
    x.output.write_text(json.dumps(config,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Generated fixed Germany route; no direct rules, selectors or controller')
