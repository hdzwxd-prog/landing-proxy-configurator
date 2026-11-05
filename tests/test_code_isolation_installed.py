"""Probe the installed WFP predicates using account-free test programs only."""
import json, os, socket, subprocess
from pathlib import Path
root=Path(os.environ['USERPROFILE'])/'.ssh/GermanyRouter/StrictGermany'
report={'production_service_stopped':False,'real_claude_launched':False,'cases':[]}
for exe,port in [('isolation-check.exe',18485),('isolation-check-offline.exe',18685)]:
    if port==18685:
        with socket.socket() as s:
            s.settimeout(.3)
            if s.connect_ex(('127.0.0.1',port))==0:raise RuntimeError('Offline probe port is unexpectedly listening')
    # A successful sendto return does not establish delivery; inspect a local receiver.
    if port==18685:
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as udp:
            udp.bind(('127.0.0.1',port));udp.settimeout(.7)
            result=subprocess.run([str(root/exe),str(port)],capture_output=True,text=True,timeout=20,creationflags=subprocess.CREATE_NO_WINDOW)
            try:udp.recvfrom(100);delivered=True
            except socket.timeout:delivered=False
    else:
        # Do not bind the live core's UDP socket or disturb its existing listener.
        result=subprocess.run([str(root/exe),str(port)],capture_output=True,text=True,timeout=20,creationflags=subprocess.CREATE_NO_WINDOW)
        delivered=None
    lines=result.stdout.splitlines()
    required=[f'TCP 127.0.0.1:{p} ERROR 10013' for p in (7892,7980,18484)]
    required+=['TCP 1.1.1.1:443 ERROR 10013',f'TCP ::1:{port} ERROR 10013']
    required += [f'TCP 127.0.0.1:{port} ALLOWED'] if port==18485 else [f'TCP 127.0.0.1:{port} ERROR 10061','TCP 127.0.0.1:18485 ERROR 10013']
    passed=result.returncode==0 and all(line in lines for line in required) and not delivered
    case={'program':exe,'allowed_port':port,'passed':passed,'tcp_observations':lines,'local_udp_received':delivered,'public_ipv6_note':'10051 indicates unavailable network, not a verified WFP denial'}
    report['cases'].append(case)
report['passed']=all(c['passed'] for c in report['cases'])
(root/'code-isolation-probe-results.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
raise SystemExit(0 if report['passed'] else 1)
