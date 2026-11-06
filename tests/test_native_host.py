"""Account-free native messaging framing/EOF test; no browser or proxy settings."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import json, struct, subprocess, unittest

class NativeHost(unittest.TestCase):
    def test_starts_disabled_and_exits_when_browser_closes(self):
        exe=Path(__file__).resolve().parents[1]/"bin/LandingEdgeNativeHost.exe"
        process=subprocess.Popen([str(exe)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE,creationflags=subprocess.CREATE_NO_WINDOW)
        try:
            def frame():
                prefix=process.stdout.read(4)
                self.assertEqual(len(prefix),4)
                size=struct.unpack("<I",prefix)[0]
                self.assertLess(size,4096)
                return json.loads(process.stdout.read(size))
            with ThreadPoolExecutor(1) as pool:
                result=pool.submit(frame).result(timeout=5)
            self.assertEqual(result,{"protocol":1,"enabled":False,"version":0})
            process.stdin.close()
            self.assertEqual(process.wait(timeout=5),0)
        finally:
            if process.poll() is None: process.kill()
            process.wait(timeout=5)
            process.stdout.close()
            process.stderr.close()

if __name__=="__main__": unittest.main()
