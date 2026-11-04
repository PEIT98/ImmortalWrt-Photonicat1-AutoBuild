#!/usr/bin/env python3
"""核对真实拨号条件及 C 数据格式处理，不需要路由器或 SIM 卡。"""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PATCH_PATH = ROOT / "scripts/patches/fix-qmodem-netifd-owner.py"
spec = importlib.util.spec_from_file_location("owner_patch", PATCH_PATH)
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)
FEED = Path(sys.argv.pop(1)).resolve() if len(sys.argv) > 1 else None


class NetifdOwnerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_patch_repeated_and_rejects_changed_upstream_before_writing(self):
        original, updated = patch.patched_files(FEED)
        self.assertEqual(original, updated, "先应用补丁再运行回归")
        copied = self.root / "feed"
        for path, content in updated.items():
            target = copied / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content)
        a, b = patch.patched_files(copied)
        self.assertEqual(a, b)
        target = copied / patch.CM / "QMIThread.c"
        target.write_text(target.read_text().replace(patch.FORMAT_NEW, "/* changed upstream */"))
        before = {p: p.read_bytes() for p in copied.rglob("*") if p.is_file()}
        result = subprocess.run([sys.executable, PATCH_PATH, copied], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("上游布局变化", result.stderr)
        self.assertEqual(before, {p: p.read_bytes() for p in before})

    def test_real_dial_ownership_conditions(self):
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        uci = bin_dir / "uci"
        uci.write_text("#!/usr/bin/env python3\nimport json,os,sys\nv=json.loads(os.environ['TEST_UCI']).get(sys.argv[-1])\nif v is None: sys.exit(1)\nprint(v)\n")
        uci.chmod(0o755)
        sysroot = self.root / "sys"
        interface = sysroot / "class/net/cell42"
        (interface / "qmi").mkdir(parents=True)
        (interface / "device").mkdir()
        generic = sysroot / "bus/usb/drivers/qmi_wwan"
        generic.mkdir(parents=True)
        driver = interface / "device/driver"
        driver.symlink_to(generic)
        raw = interface / "qmi/raw_ip"
        raw.write_text("N\n")
        capabilities = ["usr/bin/quectel-CM-M", "usr/libexec/qmodem-ipv4-event", "lib/netifd/proto/qmodem_runtime.sh"]
        for relative in capabilities:
            path = self.root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("#!/bin/sh\nexit 0\n")
            path.chmod(0o755)
        source = (FEED / patch.DIAL).read_text()
        decision = source[source.index("    managed_ipv4=0\n"):source.index('    m_debug "modem_path=', source.index("    managed_ipv4=0\n"))]
        decision = decision.replace("/usr/bin/", f"{self.root}/usr/bin/").replace("/usr/libexec/", f"{self.root}/usr/libexec/")
        script = patch.OWNER_FUNCTION + '\n' + decision + '\nprintf "%s" "$managed_ipv4"\n'
        base_config = {"qmodem.slot_dynamic.data_interface": "usb"}
        env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", driver="qmi", bridge_enabled="0", pdp_type="ipv4v6", modem_config="slot_dynamic", modem_netcard="cell42", QMODEM_SYSFS_ROOT=str(sysroot), PHOTONICAT_QMODEM_ROOT=str(self.root))

        def owner(config=None, **overrides):
            current = dict(env, TEST_UCI=json.dumps(base_config | (config or {})), **overrides)
            return subprocess.check_output(["sh", "-c", script], env=current, text=True)

        self.assertEqual(owner(), "1")
        original_decision = decision.replace("} ||\n                photonicat_netifd_owner; then", "}; then")
        self.assertNotEqual(original_decision, decision)
        original_script = patch.OWNER_FUNCTION + '\n' + original_decision + '\nprintf "%s" "$managed_ipv4"\n'
        original_env = dict(env, TEST_UCI=json.dumps(base_config))
        self.assertEqual(subprocess.check_output(["sh", "-c", original_script], env=original_env, text=True), "0", "复现原路径未启用 netifd 接管")
        for protocol in ("ecm", "mbim", "rndis", "ncm", "mhi"):
            with self.subTest(protocol=protocol):
                self.assertEqual(owner(driver=protocol), "0")
        self.assertEqual(owner(bridge_enabled="1"), "0")
        self.assertEqual(owner(pdp_type="ipv6"), "0")
        self.assertEqual(owner({"qmodem.slot_dynamic.data_interface": "pcie"}), "0")
        self.assertEqual(owner({"qmodem.slot_dynamic.host_ipv4_owner": "legacy"}), "0")
        self.assertEqual(owner({"qmodem.slot_dynamic.host_ipv4_owner": "netifd"}), "1")
        raw.unlink()
        self.assertEqual(owner(), "0")
        raw.write_text("Y\n")
        driver.unlink()
        driver.symlink_to(sysroot / "bus/usb/drivers/qmi_wwan_q")
        self.assertEqual(owner(), "0")
        driver.unlink()
        driver.symlink_to(generic)
        for relative in capabilities:
            path = self.root / relative
            path.rename(path.with_suffix(".saved"))
            self.assertEqual(owner(), "0")
            path.with_suffix(".saved").rename(path)
        hook = self.root / "usr/libexec/qmodem-host-ipv4-owner"
        hook.write_text("#!/bin/sh\nexit 0\n")
        hook.chmod(0o755)
        self.assertEqual(owner(driver="mbim"), "1", "保留上游可选管理器")

    def test_actual_cm_format_and_managed_ipv4_events(self):
        cc = os.environ.get("CC", "cc")
        source = FEED / patch.CM / "udhcpc.c"
        binary = self.root / "format-test"
        subprocess.run([cc, "-ffunction-sections", "-fdata-sections", "-Wall", "-Wextra", "-Wno-unused-parameter", f'-DQMODEM_CM_SOURCE="{source}"', ROOT / "scripts/tests/qmodem_qmi_format_harness.c", "-Wl,--gc-sections", "-pthread", "-o", binary], check=True, capture_output=True, text=True)
        subprocess.run([binary], check=True)
        managed = self.root / "managed-test"
        subprocess.run([cc, "-pthread", FEED / "application/quectel_CM_5G_M/tests/test_managed_ipv4.c", "-o", managed], check=True, capture_output=True, text=True)
        subprocess.run([managed], check=True)


if __name__ == "__main__":
    if FEED is None:
        raise SystemExit("用法：test_qmodem_netifd_owner.py QModem软件源目录")
    unittest.main()
