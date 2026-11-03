import hashlib
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('autogrow_patch', ROOT / 'scripts/patches/enable-emmc-autogrow.py')
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)


class AutoGrowBuildTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.file = self.root / patch.RELATIVE
        self.file.parent.mkdir(parents=True)
        self.file.write_bytes((ROOT / 'scripts/tests/fixtures/rockchip-platform.sh').read_bytes())
        kernel = self.root / 'target/linux/rockchip/armv8/config-6.12'
        kernel.write_bytes((ROOT / 'scripts/tests/fixtures/rockchip-storage.config').read_bytes())

    def test_both_validation_and_write_paths_keep_the_expanded_partition(self):
        patch.prepare(self.root)
        source = self.file.read_text()
        self.assertEqual(source.count('diff="$(swrt_partition_difference '), 2)
        self.assertIn('UPGRADE_OPT_SAVE_PARTITIONS', source)
        before = self.file.read_bytes()
        patch.prepare(self.root)
        self.assertEqual(self.file.read_bytes(), before)

    def test_unknown_upstream_or_modified_prepared_script_is_rejected(self):
        original = self.file.read_bytes()
        self.file.write_bytes(original.replace(b'platform_check_image', b'unknown_check_image'))
        with self.assertRaises(ValueError): patch.prepare(self.root)
        self.file.write_bytes(original)
        patch.prepare(self.root)
        self.file.write_bytes(self.file.read_bytes() + b'# drift\n')
        with self.assertRaises(ValueError): patch.prepare(self.root)

    def test_first_boot_tools_and_hook_are_packaged(self):
        config = (ROOT / 'photonicat1.config').read_text()
        for name in ('sfdisk', 'partx-utils', 'blockdev', 'losetup', 'resize2fs', 'f2fsck'):
            self.assertIn('CONFIG_PACKAGE_' + name + '=y', config)
        hook = ROOT / 'files/lib/preinit/79-swrt-autogrow'
        self.assertTrue(hook.exists())
        self.assertIn('preinit_main swrt_autogrow_preinit', hook.read_text())
        self.assertFalse((ROOT / 'files/usr/libexec/swrt-storage').exists())

    def test_unrelated_upstream_comments_do_not_break_builds(self):
        self.file.write_bytes(self.file.read_bytes() + b"# harmless upstream documentation\n")
        patch.prepare(self.root)
        self.assertIn("swrt_partition_difference", self.file.read_text())

    def test_preinit_storage_drivers_must_remain_builtin(self):
        kernel = self.root / 'target/linux/rockchip/armv8/config-6.12'
        kernel.write_text(kernel.read_text().replace('CONFIG_BLK_DEV_LOOP=y', 'CONFIG_BLK_DEV_LOOP=m'))
        with self.assertRaisesRegex(ValueError, 'must be built in'):
            patch.prepare(self.root)


@unittest.skipIf(os.name == 'nt', 'POSIX partition comparison runs on Linux')
class UpgradePartitionTests(unittest.TestCase):
    def compare(self, disk, image):
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            boot = folder / 'boot'; boot.write_text(disk)
            img = folder / 'image'; img.write_text(image)
            source = (ROOT / 'patches/rockchip/swrt-upgrade-partitions.sh').read_text()
            result = subprocess.run(['sh', '-c', source + '\nswrt_partition_difference "$1" "$2"\n',
                                     'sh', str(boot), str(img)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout.strip()

    def test_8g_16g_64g_grown_root_is_compatible(self):
        image = '1 65536 32768\n2 131072 2097152\n'
        for gib in (8, 16, 64):
            with self.subTest(gib=gib):
                self.assertEqual(self.compare(f'1 65536 32768\n2 131072 {gib*1024**3//512-131072}\n', image), '')

    def test_extra_user_partition_is_not_an_upgrade_target(self):
        self.assertEqual(self.compare('1 65536 32768\n2 131072 8257536\n3 8388608 1048576\n',
                                      '1 65536 32768\n2 131072 2097152\n'), '')

    def test_official_cross_layout_and_undersized_root_still_rejected(self):
        image = '1 65536 32768\n2 131072 2097152\n'
        for old in ('1 65536 131072\n2 262144 8388608\n',
                    '1 65536 32768\n2 131072 1048576\n', ''):
            self.assertNotEqual(self.compare(old, image), '')
        self.assertNotEqual(self.compare(image, ''), '')

    def test_malformed_duplicate_and_overlapping_existing_tables_are_rejected(self):
        image = '1 65536 32768\n2 131072 2097152\n'
        for disk in ('1 65536 32768\n2 131072 -1\n',
                     '1 65536 32768\n2 131072 2097152\n2 131072 9999999\n',
                     '1 65536 32768\n2 131072 8257536\n3 5000000 1048576\n'):
            with self.subTest(disk=disk):
                self.assertNotEqual(self.compare(disk, image), '')


if __name__ == '__main__': unittest.main()
