import importlib.util, unittest
from pathlib import Path
spec=importlib.util.spec_from_file_location('strict_config',Path(__file__).parents[1]/'strict/generate_config.py')
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)

class StrictConfigTests(unittest.TestCase):
    def setUp(self):
        self.source={'proxies':[{'name':'Germany-VLESS','type':'vless','server':'192.248.188.234','port':443,'dialer-proxy':'FIRST-HOP'}, {'name':'Other','type':'direct'}], 'rules':['MATCH,DIRECT']}
    def test_no_selectors_direct_or_alternate_exits(self):
        d=mod.generate(self.source,'127.0.0.1:7892')
        self.assertEqual(d['rules'],['MATCH,Germany-VLESS'])
        self.assertEqual(len(d['proxies']),2)
        self.assertNotIn('proxy-groups',d);self.assertNotIn('external-controller',d)
        self.assertEqual(d['proxies'][1]['dialer-proxy'],'STRICT-UPSTREAM')
        self.assertEqual(self.source['proxies'][0]['dialer-proxy'],'FIRST-HOP')
    def test_reject_self_loop_and_remote_upstream(self):
        for endpoint in ('127.0.0.1:18484','127.0.0.1:18485','192.0.2.1:7892','127.0.0.1:0'):
            with self.assertRaises(ValueError):mod.generate(self.source,endpoint)
    def test_reject_replaced_landing(self):
        self.source['proxies'][0]['server']='212.121.132.230'
        with self.assertRaises(ValueError):mod.generate(self.source,'127.0.0.1:7980')

if __name__=='__main__':unittest.main()
