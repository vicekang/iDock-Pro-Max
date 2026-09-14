"""Exercise the actual detached module script against a fake sysfs tree."""
import json
import os
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class PortableSessionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        build = Path(cls.build.name)
        (build / "main.swift").write_text('import Foundation\nlet value: [String: Any] = ["script": ModulePortabilityPolicy.sessionScript, "supported": [ModulePortabilityPolicy.supports(firmware: "QDC507GLEFM21_01.001.01.009"), ModulePortabilityPolicy.supports(firmware: "QDC507GLEFM21_01.001.01.007"), ModulePortabilityPolicy.supports(firmware: "prefixQDC507GLEFM21_01.001.01.009"), ModulePortabilityPolicy.supports(firmware: nil)]]\nprint(String(data: try JSONSerialization.data(withJSONObject: value), encoding: .utf8)!)\n')
        subprocess.run(["swiftc", str(ROOT / "Sources/CellDock/ModulePortabilityPolicy.swift"), str(build / "main.swift"), "-o", str(build / "export")], check=True)
        cls.policy = json.loads(subprocess.check_output([str(build / "export")]))

    @classmethod
    def tearDownClass(cls):
        cls.build.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.base = self.root / "usb"
        self.base.mkdir()
        (self.root / "run").mkdir()
        self.write("functions", "diag,serial,ecm,ffs")
        self.write("enable", "1")
        self.write("state", "CONFIGURED")
        (self.root / "audio_enable").write_text("0")
        (self.root / "present").write_text("1")
        script = self.policy["script"].replace("/sys/class/android_usb/android0", str(self.base)).replace("/sys/class/android_usb/f_audio/audio_enable", str(self.root / "audio_enable")).replace("/run/celldock-portable", str(self.root / "run"))
        self.script = self.root / "session.sh"
        script = script.replace("/sys/class/power_supply/usb/present", str(self.root / "present"))
        self.script.write_text(script)
        self.process = None

    def tearDown(self):
        if self.process and self.process.poll() is None:
            self.process.send_signal(signal.SIGTERM)
            try:
                self.process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                self.process.wait()
        self.temp.cleanup()

    def write(self, name, value):
        (self.base / name).write_text(value)

    def wait_for(self, predicate):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(.03)
        self.fail("session did not reach expected state")

    def launch(self):
        self.process = subprocess.Popen(["/bin/sh", str(self.script)], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def test_firmware_whitelist_is_exact(self):
        self.assertEqual(self.policy["supported"], [True, False, False, False])

    def test_mac_audio_and_powered_usb_detach(self):
        self.launch()
        self.wait_for(lambda: (self.base / "functions").read_text() == "diag,serial,ecm,ffs,audio")
        time.sleep(.3)
        self.write("state", "DISCONNECTED")
        self.assertEqual(self.process.wait(timeout=5), 0)
        self.assertEqual((self.base / "functions").read_text(), "diag,serial,ecm,ffs")
        self.assertEqual((self.base / "enable").read_text(), "1")
        self.assertFalse((self.root / "run/pid").exists())

    def test_restart_on_existing_mac_session_and_term_restore(self):
        self.write("functions", "diag,serial,ecm,ffs,audio")
        self.launch()
        self.wait_for(lambda: (self.root / "run/started").exists())
        self.assertEqual((self.base / "functions").read_text(), "diag,serial,ecm,ffs,audio")
        self.process.terminate()
        self.process.wait(timeout=3)
        self.assertEqual((self.base / "functions").read_text(), "diag,serial,ecm,ffs")

    def test_brief_reenumeration_does_not_remove_mac_audio(self):
        self.write("functions", "diag,serial,ecm,ffs,audio")
        self.launch()
        self.wait_for(lambda: (self.root / "run/started").exists())
        time.sleep(.3)
        self.write("state", "DISCONNECTED")
        time.sleep(.5)
        self.write("state", "CONFIGURED")
        time.sleep(.4)
        self.assertIsNone(self.process.poll())
        self.assertEqual((self.base / "functions").read_text(), "diag,serial,ecm,ffs,audio")

    def test_vbus_loss_restores_phone_profile(self):
        self.write("functions", "diag,serial,ecm,ffs,audio")
        self.launch()
        self.wait_for(lambda: (self.root / "run/started").exists())
        (self.root / "present").write_text("0")
        self.assertEqual(self.process.wait(timeout=2), 0)
        self.assertEqual((self.base / "functions").read_text(), "diag,serial,ecm,ffs")

    def test_unknown_composition_untouched(self):
        self.write("functions", "rndis,ffs")
        self.launch()
        self.assertEqual(self.process.wait(timeout=3), 20)
        self.assertEqual((self.base / "functions").read_text(), "rndis,ffs")
        self.assertEqual((self.base / "enable").read_text(), "1")

    def test_active_audio_rejected_without_disconnect(self):
        (self.root / "audio_enable").write_text("1")
        self.launch()
        self.assertEqual(self.process.wait(timeout=3), 22)
        self.assertEqual((self.base / "functions").read_text(), "diag,serial,ecm,ffs")
        self.assertEqual((self.base / "enable").read_text(), "1")

    def test_other_configuration_owner_is_preserved(self):
        self.write("functions", "diag,serial,ecm,ffs,audio")
        self.launch()
        self.wait_for(lambda: (self.root / "run/started").exists())
        self.write("functions", "rndis,ffs")
        self.process.wait(timeout=3)
        self.assertEqual((self.base / "functions").read_text(), "rndis,ffs")
        self.assertEqual((self.base / "enable").read_text(), "1")


if __name__ == "__main__":
    unittest.main()
