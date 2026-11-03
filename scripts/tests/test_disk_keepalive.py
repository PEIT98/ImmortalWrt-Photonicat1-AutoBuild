import json
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / 'packages/luci-app-swrt-disk-keepalive'


class DiskKeepaliveTests(unittest.TestCase):
    def test_inventory_and_replug_without_real_block_devices(self):
        result = subprocess.run(['sh', str(ROOT / 'scripts/tests/disk_keepalive_harness.sh'),
                                 str(APP / 'root/usr/share/swrt-disk-keepalive/common.sh')],
                                env={**os.environ, 'SWRT_DISK_QA_IDENTITY_ONLY': '1'},
                                text=True, capture_output=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_readonly_permissions_and_no_default_target(self):
        acl = json.loads((APP / 'root/usr/share/rpcd/acl.d/luci-app-swrt-disk-keepalive.json').read_text(encoding='utf-8'))
        role = acl['luci-app-swrt-disk-keepalive']
        self.assertEqual(role['read']['ubus']['luci.swrt_disk_keepalive'], ['status'])
        self.assertEqual(role['write']['ubus']['luci.swrt_disk_keepalive'], ['configure', 'test'])
        default = (APP / 'root/etc/config/swrt_disk_keepalive').read_text(encoding='utf-8')
        self.assertIn("option enabled '0'", default)
        self.assertNotIn('list device', default)

    @unittest.skipIf(os.name == 'nt', 'Linux shell and loop device test')
    def test_real_direct_io_and_disk_identity(self):
        if os.geteuid() != 0 or not all(shutil.which(x) for x in ['jq', 'losetup', 'timeout', 'dd']):
            self.skipTest('Root, jq, losetup and coreutils are required')
        if not Path('/dev/loop-control').exists():
            self.skipTest('Disposable loop devices are unavailable in this executor')
        result = subprocess.run(['sh', str(ROOT / 'scripts/tests/disk_keepalive_harness.sh'),
                                 str(APP / 'root/usr/share/swrt-disk-keepalive/common.sh')],
                                env={**os.environ, 'SWRT_DISK_QA_IDENTITY_ONLY': '0'},
                                text=True, capture_output=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
