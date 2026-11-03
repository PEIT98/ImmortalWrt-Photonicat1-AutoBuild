"""Exercise production partition logic with private fixtures and no block writes."""
import importlib.util
import json
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("emmc_patch", ROOT / "scripts/patches/enable-emmc-autogrow.py")
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)


class StorageIntegrationTests(unittest.TestCase):
    def test_regex_provider_and_all_runtime_tools_are_selected(self):
        config = (ROOT / "photonicat1.config").read_text()
        self.assertIn("# CONFIG_PACKAGE_jq is not set", config)
        for name in ("jq-full", "coreutils-dd", "coreutils-timeout", "coreutils-stat",
                     "sfdisk", "partx-utils", "blockdev", "blkid", "losetup",
                     "resize2fs", "f2fsck", "mkf2fs"):
            self.assertIn("CONFIG_PACKAGE_" + name + "=y", config)
        self.assertIn("CONFIG_BUSYBOX_CONFIG_HEXDUMP=y", config)

    def test_tools_are_self_contained_and_do_not_pull_a_network_panel(self):
        for name in ("luci-app-online-upgrade", "luci-app-swrt-disk-keepalive"):
            app = ROOT / "packages" / name
            self.assertNotIn("+wlmb-server", (app / "Makefile").read_text())
            for view in (app / "root/www/luci-static/resources/view/system").glob("*.js"):
                for asset in re.findall(r"L\.resource\('([^']+)'\)", view.read_text()):
                    self.assertTrue((app / "root/www/luci-static/resources" / asset).is_file(), asset)

    def plan(self, *, extra=False, overlapping=False):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            root = folder / "mmcblk0p2"
            root.touch()
            parts = [{"node": str(folder / "mmcblk0p1"), "start": 65536, "size": 32768, "type": "83"},
                     {"node": str(root), "start": 131072, "size": 2097152, "type": "83"}]
            if extra:
                parts.append({"node": str(folder / "mmcblk0p3"),
                              "start": 1000000 if overlapping else 8388608,
                              "size": 1048576, "type": "83"})
            table = {"partitiontable": {"label": "dos", "sectorsize": 512, "id": "0x5452574f",
                                       "partitions": parts}}
            fixture = folder / "table.json"
            fixture.write_text(json.dumps(table))
            source = (ROOT / "files/usr/libexec/swrt-autogrow").read_text()
            self.assertTrue(source.rstrip().endswith('main "$@"'))
            source = source.rsplit('main "$@"', 1)[0]
            harness = f'''
WORK='{folder}'
root='{root}'
disk='/unused-fixture-only'
sectors=33554432
log() {{ :; }}
sfdisk() {{ cat '{fixture}'; }}
plan
cat "$WORK/plan.json"
'''
            return subprocess.run(["sh", "-c", source + harness], text=True, capture_output=True)

    def test_production_plan_uses_all_contiguous_emmc_space(self):
        result = self.plan()
        self.assertEqual(result.returncode, 0, result.stderr)
        plan = json.loads(result.stdout)
        self.assertEqual(plan["new_size"], 33554432 - 131072)
        self.assertEqual(plan["start"], 131072)

    def test_production_plan_stops_before_an_extra_partition(self):
        result = self.plan(extra=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["new_size"], 8388608 - 131072)

    def test_production_plan_rejects_overlapping_partitions(self):
        result = self.plan(extra=True, overlapping=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("overlapping partition layout", result.stderr)

    def test_native_upgrade_writes_only_image_partitions_and_disk_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            platform = folder / patch.RELATIVE
            platform.parent.mkdir(parents=True)
            platform.write_bytes((ROOT / "scripts/tests/fixtures/rockchip-platform.sh").read_bytes())
            kernel = folder / "target/linux/rockchip/armv8/config-6.12"
            kernel.write_bytes((ROOT / "scripts/tests/fixtures/rockchip-storage.config").read_bytes())
            patch.prepare(folder)
            source = platform.read_text().replace("/tmp/", str(folder) + "/")
            boot = folder / "fixture.boot"
            image = folder / "fixture.image"
            boot.write_text("1 65536 32768\n2 131072 8257536\n3 8388608 1048576\n")
            image.write_text("1 65536 32768\n2 131072 2097152\n")
            log = folder / "calls"
            harness = f'''
export_bootdevice() {{ return 0; }}
export_partdevice() {{ eval "$1=fixture-part$2"; }}
get_partitions() {{ cp '{folder}/fixture.'"$2" '{folder}/partmap.'"$2"; }}
get_image() {{ printf 'fixture bytes'; }}
dd() {{ cat >/dev/null; printf '%s\\n' "$*" >>'{log}'; }}
partx() {{ printf 'UNEXPECTED PARTX\\n' >>'{log}'; }}
ask_bool() {{ return 1; }}
sync() {{ :; }}
UPGRADE_OPT_SAVE_PARTITIONS=1
platform_check_image fixture.img
platform_do_upgrade fixture.img
'''
            # Map native bootdisk argument to our fixture; dd is always a shell
            # stub, so not a single real /dev device can be opened by this test.
            harness = harness.replace("fixture.boot", "fixture.bootdisk")
            boot.rename(folder / "fixture.bootdisk")
            result = subprocess.run(["sh", "-c", source + harness], text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            calls = log.read_text().splitlines()
            self.assertTrue(any("of=/dev/fixture-part1" in line and "count=32768" in line for line in calls))
            self.assertTrue(any("of=/dev/fixture-part2" in line and "count=2097152" in line for line in calls))
            self.assertTrue(any("of=/dev/fixture-part0" in line and "count=4" in line for line in calls))
            self.assertFalse(any("fixture-part3" in line or "UNEXPECTED" in line for line in calls))


if __name__ == "__main__":
    unittest.main()
