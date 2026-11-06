"""Boundary regression checks; no real service, registry mutation, or account traffic."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

class Boundaries(unittest.TestCase):
    def test_runtime_does_not_write_windows_proxy(self):
        for name in ("GermanyProxyManager.cs", "Start-Germany-Router.ps1", "Stop-Germany-Proxy.ps1"):
            text = (ROOT / name).read_text(encoding="utf-8-sig")
            for forbidden in ('SetValue("Proxy', "SetValue('Proxy", "-Name ProxyEnable",
                              "-Name ProxyServer", "-Name ProxyOverride", "Set-SystemProxy"):
                self.assertNotIn(forbidden, text, (name, forbidden))

    def test_runtime_does_not_enable_legacy_edge_policy(self):
        text = (ROOT / "GermanyProxyManager.cs").read_text(encoding="utf-8-sig")
        self.assertNotIn("Configure-Edge-Landing.ps1", text)
        self.assertIn("edgeLease.SetEnabled(enable)", text)
        self.assertIn("edgeLease.Dispose()", text)

    def test_stop_is_checked_not_fire_and_forget(self):
        text = (ROOT / "GermanyProxyManager.cs").read_text(encoding="utf-8-sig")
        block = text.split("private static void RunCleanup(")[1].split("private static void RunRestart")[0]
        self.assertNotIn("RunHidden(", block)
        self.assertIn("RunHiddenChecked(", block)

if __name__ == "__main__":
    unittest.main()
