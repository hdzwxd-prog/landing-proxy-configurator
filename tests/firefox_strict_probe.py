"""Inspect the installed Firefox through its temporary local Marionette test port.

Only use during an authorized browser test. Disable Marionette by restarting
Firefox normally when finished. No credentials or account pages are inspected.
"""
import json, socket, time, argparse

class Marionette:
    def __init__(self):
        self.s=socket.create_connection(('127.0.0.1',2828),5); self.s.settimeout(50); self.seq=0
        self.recv()
        self.call('WebDriver:NewSession',{'capabilities':{'alwaysMatch':{'acceptInsecureCerts':False}}})
        self.call('WebDriver:SetTimeouts',{'pageLoad':25000,'script':20000})
    def recv(self):
        size=b''
        while not size.endswith(b':'):
            part=self.s.recv(1)
            if not part: raise ConnectionError('Marionette closed')
            size+=part
        data=b''
        while len(data)<int(size[:-1]): data+=self.s.recv(int(size[:-1])-len(data))
        return json.loads(data)
    def call(self,command,params=None):
        self.seq+=1;data=json.dumps([0,self.seq,command,params or {}]).encode()
        self.s.sendall(str(len(data)).encode()+b':'+data)
        reply=self.recv()
        if reply[1]!=self.seq:raise RuntimeError('Unexpected reply id')
        if reply[2]:raise RuntimeError(reply[2]['message'][:400])
        return reply[3]
    def script(self,script):return self.call('WebDriver:ExecuteScript',{'script':script,'args':[],'newSandbox':True})

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--mode',choices=['policy','exit','blocked','quit'],required=True);a=p.parse_args()
    m=Marionette()
    try:
        if a.mode=='quit':m.call('Marionette:Quit',{'flags':['eAttemptQuit']})
        elif a.mode=='policy':
            m.call('Marionette:SetContext',{'value':'chrome'})
            print(json.dumps(m.script('''
                const names=["network.proxy.type","network.proxy.http","network.proxy.http_port","network.proxy.ssl","network.proxy.ssl_port","network.proxy.no_proxies_on","network.proxy.failover_direct","media.peerconnection.enabled","network.http.http3.enable","network.trr.mode","geo.enabled"];
                return {policies:Services.policies.getActivePolicies(), prefs:names.map(n=>({name:n,locked:Services.prefs.prefIsLocked(n),value:Services.prefs.getPrefType(n)==128?Services.prefs.getBoolPref(n):Services.prefs.getPrefType(n)==64?Services.prefs.getIntPref(n):Services.prefs.getStringPref(n)}))};
            '''),ensure_ascii=False))
        else:
            url='https://api.ipify.org/?strict_test='+str(time.time_ns())
            failed=False
            try:m.call('WebDriver:Navigate',{'url':url})
            except RuntimeError as e:failed=True;print('navigation_error',str(e))
            print(json.dumps(m.script('return {url:document.documentURI,text:document.body.innerText.slice(0,800)};'),ensure_ascii=False))
            if a.mode=='blocked' and not failed:raise RuntimeError('Expected blocked navigation')
    finally:
        if a.mode!='quit':
            try:m.call('WebDriver:DeleteSession')
            except Exception:pass
        m.s.close()
