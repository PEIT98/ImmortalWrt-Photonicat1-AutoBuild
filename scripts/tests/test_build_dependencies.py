"""Regress the observed Kconfig provider cycle and native disk word reads."""
import importlib.util
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("weechat_fix", ROOT / "scripts/patches/fix-weechat-provider.py")
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)


class DependencyTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.app = self.root / "feeds/luci/applications/luci-app-weechat/Makefile"
        self.app.parent.mkdir(parents=True)
        self.original = (
            "# Apache-2.0 upstream frontend recipe\n"
            "LUCI_TITLE:=LuCI support for WeeChat IRC client\n"
            "LUCI_DEPENDS:=+luci-base +weechat +rpcd-mod-ucode\n"
        )
        self.app.write_text(self.original)
        self.provider = self.root / "feeds/packages/net/weechat/Makefile"
        self.provider.parent.mkdir(parents=True)
        self.provider.write_text("define Package/weechat-minimal\n DEFAULT_VARIANT:=1\n PROVIDES:=weechat\nendef\n")

    def test_virtual_default_is_replaced_with_the_real_provider_only_once(self):
        patch.prepare(self.root)
        expected = self.original.replace("+weechat ", "+weechat-minimal ")
        self.assertEqual(self.app.read_text(), expected)
        patch.prepare(self.root)
        self.assertEqual(self.app.read_text(), expected)

    def test_fixed_upstream_concrete_provider_is_preserved(self):
        current = self.original.replace("+weechat ", "+weechat-full ")
        self.app.write_text(current)
        patch.prepare(self.root)
        self.assertEqual(self.app.read_text(), current)

    def test_missing_provider_does_not_modify_the_frontend(self):
        self.provider.unlink()
        with self.assertRaises(ValueError):
            patch.prepare(self.root)
        self.assertEqual(self.app.read_text(), self.original)

    def test_disk_word_reads_use_a_declared_package_not_hidden_busybox_options(self):
        config = (ROOT / "photonicat1.config").read_text()
        verifier = (ROOT / "scripts/build/verify-config.sh").read_text()
        self.assertIn("CONFIG_PACKAGE_coreutils-od=y", config)
        self.assertIn("CONFIG_PACKAGE_coreutils-od", verifier)
        self.assertNotIn("CONFIG_BUSYBOX_CONFIG_HEXDUMP", config + verifier)
        source = (ROOT / "files/usr/libexec/swrt-autogrow").read_text().rsplit('main "$@"', 1)[0]
        data = self.root / "superblock.fixture"
        payload = bytearray(32)
        struct.pack_into("<I", payload, 4, 0xDEADBEEF)
        struct.pack_into("<Q", payload, 12, 0x1122334455667788)
        data.write_bytes(payload)
        result = subprocess.run(["sh", "-c", source + '\nu32 "$1" 4\nu64 "$1" 12\n', "sh", str(data)],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [str(0xDEADBEEF), str(0x1122334455667788)])
        result = subprocess.run(["sh", "-c", source + '\nu64 "$1" 28\n', "sh", str(data)],
                                text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0, "A short superblock read must fail")


if __name__ == "__main__":
    unittest.main()
