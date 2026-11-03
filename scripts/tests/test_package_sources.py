"""Run the production mirror helper against private configuration fixtures."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "packages/luci-app-photonicat-power"
ENGINE = APP / "root/usr/libexec/photonicat-package-source"
OFFICIAL = "https://downloads.immortalwrt.org"
NJU = "https://mirror.nju.edu.cn/immortalwrt"


class PackageSourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for name in ("bin", "etc/config", "etc/apk/repositories.d", "tmp/sysinfo",
                     "usr/share/photonicat", "var/lock"):
            (self.root / name).mkdir(parents=True)
        shutil.copy2(APP / "root/usr/share/photonicat/package-sources.awk",
                     self.root / "usr/share/photonicat/package-sources.awk")
        self.config = self.root / "etc/config/photonicat_packages"
        self.config.write_text("config settings 'main'\n\toption source 'nju'\n")
        (self.root / "tmp/sysinfo/board_name").write_text("ariaboard,photonicat\n")
        self.feed = self.root / "etc/apk/repositories.d/distfeeds.list"
        self.original = (
            "# Preserve comment: https://downloads.immortalwrt.org/releases\n"
            "https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/targets/rockchip/armv8/packages/packages.adb\n"
            "@base\thttps://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_generic/base/packages.adb  # keep spaces\n"
            "https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/targets/rockchip/armv8/kmods/6.12.112-1-abcdef/packages.adb\n"
            "https://repo.istoreos.com/istore/compatible/aarch64_generic/packages.adb\n"
            "https://downloads.immortalwrt.org.evil.invalid/custom/packages.adb\n"
        )
        self.feed.write_text(self.original)
        self.feed.chmod(0o644)
        self.executable("uci", r'''#!/usr/bin/env python3
import json,os,pathlib,re,sys
root=pathlib.Path(os.environ['PHOTONICAT_PACKAGE_ROOT'])
args=sys.argv[1:]; config=root/'etc/config'; staging=root/'global-uci'
while args and args[0].startswith('-'):
    flag=args.pop(0)
    if flag in ('-c','-t'):
        value=pathlib.Path(args.pop(0))
        if flag=='-c': config=value
        else: staging=value
action,key=args[:2]
file=config/'photonicat_packages'; delta=staging/'photonicat_packages'
values=dict(re.findall(r"option ([a-z_]+) '([^']*)'",file.read_text())) if file.exists() else {}
if action=='get':
    option=key.rsplit('.',1)[-1]
    if option not in values: sys.exit(1)
    print(values[option])
elif action=='set':
    staging.mkdir(parents=True,exist_ok=True)
    values=json.loads(delta.read_text()) if delta.exists() else values
    setting,value=key.split('=',1)
    if setting.startswith('photonicat_packages.main.'): values[setting.rsplit('.',1)[-1]]=value
    delta.write_text(json.dumps(values))
elif action=='commit':
    if (root/'uci-fail').exists(): sys.exit(7)
    values=json.loads(delta.read_text())
    file.write_text("config settings 'main'\n"+''.join("\toption "+k+" '"+v+"'\n" for k,v in values.items()))
    delta.unlink()
else: sys.exit(1)
''')
        self.executable("apk", "#!/bin/sh\ntouch \"$PHOTONICAT_PACKAGE_ROOT/unexpected-package-action\"\n")
        self.env = {**os.environ, "PHOTONICAT_PACKAGE_ROOT": str(self.root),
                    "PATH": str(self.root / "bin") + ":" + os.environ["PATH"]}

    def executable(self, name, source):
        path = self.root / "bin" / name
        path.write_text(source)
        path.chmod(0o755)

    def run_engine(self, action="status", data=None, raw=None):
        result = subprocess.run(["sh", str(ENGINE), action], env=self.env,
                                input=raw if raw is not None else (json.dumps(data) if data is not None else None),
                                capture_output=True, text=True, timeout=8)
        return result, json.loads(result.stdout)

    def ok(self, action="status", data=None):
        result, value = self.run_engine(action, data)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(value["ok"], value)
        return value

    def test_status_is_readonly_and_detects_unapplied_factory_mirror(self):
        original = self.config.read_bytes()
        value = self.ok()
        self.assertEqual(value["source"], "nju")
        self.assertEqual(value["actual"], "official")
        self.assertEqual(value["repositories"], 3)
        self.assertEqual(value["custom_repositories"], 2)
        self.assertTrue(value["pending"])
        self.assertEqual(self.config.read_bytes(), original)
        self.assertEqual(self.feed.read_text(), self.original)
        self.assertFalse((self.root / "unexpected-package-action").exists())

    def test_apply_uses_factory_accelerator_and_keeps_paths_and_other_sources(self):
        value = self.ok("apply")
        self.assertEqual(value["changed"], 3)
        self.assertEqual(value["actual"], "nju")
        expected = self.original.splitlines()
        for i in (1, 2, 3):
            expected[i] = expected[i].replace(OFFICIAL, NJU)
        self.assertEqual(self.feed.read_text(), "\n".join(expected) + "\n")
        self.assertEqual(self.feed.stat().st_mode & 0o777, 0o644)
        self.assertFalse((self.root / "unexpected-package-action").exists())

    def test_switch_to_official_and_reboot_apply_keep_the_saved_preference(self):
        self.ok("apply")
        value = self.ok("set", {"source": "official"})
        self.assertEqual(value["source"], "official")
        self.assertEqual(self.feed.read_text(), self.original)
        self.assertEqual(self.ok("apply")["changed"], 0)
        self.assertIn("option source 'official'", self.config.read_text())

    def test_idempotent_apply_does_not_rewrite_repository_files(self):
        self.ok("apply")
        before = self.feed.stat().st_mtime_ns
        self.assertEqual(self.ok("apply")["changed"], 0)
        self.assertEqual(self.feed.stat().st_mtime_ns, before)

    def test_preserved_mirror_setting_is_applied_to_new_distribution_lists(self):
        self.ok("apply")
        self.feed.write_text(self.original)
        self.assertTrue(self.ok()["pending"])
        self.ok("apply")
        self.assertEqual(self.ok()["actual"], "nju")

    def test_alternate_list_formats_and_opkg_compatibility_preserve_tags(self):
        primary = self.root / "etc/apk/repositories"
        primary.write_text("@test " + OFFICIAL + "/snapshots/packages/aarch64_generic/base\n")
        alternative = self.root / "etc/apk/repositories.d/extra.repositories"
        alternative.write_text("https://mirrors.nju.edu.cn/immortalwrt/releases/25.12-SNAPSHOT/packages/aarch64_generic/luci/packages.adb\n")
        opkg = self.root / "etc/opkg/distfeeds.conf"
        opkg.parent.mkdir()
        opkg.write_text("src/gz immortalwrt_base " + OFFICIAL + "/releases/25.12-SNAPSHOT/packages/aarch64_generic/base\n")
        self.ok("set", {"source": "official"})
        self.assertIn(OFFICIAL + "/releases/25.12-SNAPSHOT/packages/aarch64_generic/luci/", alternative.read_text())
        self.ok("set", {"source": "nju"})
        self.assertEqual(primary.read_text(), "@test " + NJU + "/snapshots/packages/aarch64_generic/base\n")
        self.assertEqual(opkg.read_text(), "src/gz immortalwrt_base " + NJU + "/releases/25.12-SNAPSHOT/packages/aarch64_generic/base\n")

    def test_malformed_requests_never_change_sources_or_configuration(self):
        before = self.config.read_bytes()
        for value in ("{}", "[]", '{"source":null}', '{"source":true}', '{"source":"https://example.com"}',
                      '{"source":"official; reboot"}', '{"source":"nju"}{"source":"official"}', "x" * 5000):
            with self.subTest(value=value[:40]):
                result, reply = self.run_engine("set", raw=value)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(reply["ok"])
                self.assertEqual(self.config.read_bytes(), before)
                self.assertEqual(self.feed.read_text(), self.original)

    def test_custom_only_sources_are_not_replaced(self):
        self.feed.write_text("https://my-custom.invalid/immortalwrt/packages.adb\n")
        before = self.config.read_bytes()
        result, reply = self.run_engine("set", {"source": "official"})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(reply["ok"])
        self.assertEqual(self.feed.read_text(), "https://my-custom.invalid/immortalwrt/packages.adb\n")
        self.assertEqual(self.config.read_bytes(), before)

    def test_uci_failure_rolls_back_all_repository_files(self):
        other = self.root / "etc/apk/repositories.d/second.list"
        other.write_text(OFFICIAL + "/snapshots/packages/aarch64_generic/luci\n")
        before = other.read_bytes()
        config = self.config.read_bytes()
        (self.root / "uci-fail").touch()
        result, reply = self.run_engine("set", {"source": "nju"})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(reply["ok"])
        self.assertEqual(self.feed.read_text(), self.original)
        self.assertEqual(other.read_bytes(), before)
        self.assertEqual(self.config.read_bytes(), config)

    def test_concurrent_write_is_rejected(self):
        with (self.root / "var/lock/photonicat-package-source.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            result, reply = self.run_engine("set", {"source": "official"})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(reply["ok"])
        self.assertEqual(self.feed.read_text(), self.original)

    def test_symlink_repository_targets_are_not_followed(self):
        target = self.root / "protected"
        target.write_text(self.original)
        self.feed.unlink()
        self.feed.symlink_to(target)
        result, reply = self.run_engine("set", {"source": "official"})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(reply["ok"])
        self.assertTrue(self.feed.is_symlink())
        self.assertEqual(target.read_text(), self.original)

    def test_unrelated_uci_changes_are_not_committed(self):
        pending = self.root / "global-uci"
        pending.mkdir()
        other = pending / "network"
        other.write_text("pending user network changes\n")
        self.ok("set", {"source": "nju"})
        self.assertEqual(other.read_text(), "pending user network changes\n")

    def test_missing_configuration_is_recreated(self):
        self.config.unlink()
        self.assertEqual(self.ok("set", {"source": "nju"})["source"], "nju")
        self.assertIn("option source 'nju'", self.config.read_text())

    def test_rpc_types_permissions_and_package_integration(self):
        rpc = APP / "root/usr/libexec/rpcd/luci.photonicat_packages"
        signature = subprocess.check_output(["sh", str(rpc), "list"], text=True)
        self.assertEqual(json.loads(signature)["setSettings"], {"source": ""})
        acl = json.loads((APP / "root/usr/share/rpcd/acl.d/luci-app-photonicat-power.json").read_text())["luci-app-photonicat-power"]
        self.assertEqual(acl["read"]["ubus"]["luci.photonicat_packages"], ["getSettings"])
        self.assertEqual(acl["write"]["ubus"]["luci.photonicat_packages"], ["setSettings"])
        recipe = (APP / "Makefile").read_text()
        for filename in ("photonicat-package-source", "package-sources.awk", "photonicat_packages", "99-photonicat-package-source"):
            self.assertIn(filename, recipe)
        self.assertIn("+jq-full +flock", recipe)
        self.assertIn("option source 'nju'", (APP / "root/etc/config/photonicat_packages").read_text())


if __name__ == "__main__":
    unittest.main()
