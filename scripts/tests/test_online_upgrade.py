import gzip
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "packages/luci-app-online-upgrade/root"
ENGINE = PACKAGE / "usr/libexec/swrt-upgrade"
REPO = "PEIT98/ImmortalWrt-Photonicat1-AutoBuild"


class FirmwareIdentityTests(unittest.TestCase):
    def test_rpcd_signature_uses_json_value_types_not_string_type_names(self):
        rpc = (PACKAGE / "usr/libexec/rpcd/luci.swrt_upgrade").read_text()
        upgrade = json.loads(re.search(r"'(\{\"status\"[^\n]+\})'", rpc).group(1))
        self.assertIs(type(upgrade["install"]["keep"]), int)
        self.assertIs(type(upgrade["set_source"]["source"]), str)
        self.assertIs(type(upgrade["set_channel"]["channel"]), str)

    def test_stamped_version_matches_release_and_rejects_invalid_versions(self):
        spec = importlib.util.spec_from_file_location("stamp", ROOT / "scripts/build/stamp-firmware.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            module.stamp(directory, "photonicat1-20261102-222244-55", "a" * 40)
            data = json.loads((Path(directory) / "files/etc/photonicat-release.json").read_text())
            self.assertEqual(data, {"repository": REPO, "board": "ariaboard,photonicat",
                                    "version": "photonicat1-20261102-222244-55", "commit": "a" * 40})
            with self.assertRaises(ValueError):
                module.stamp(directory, "1.10", "a" * 40)

    def test_readonly_acl_cannot_start_download_or_flash(self):
        acl = json.loads((PACKAGE / "usr/share/rpcd/acl.d/luci-app-online-upgrade.json").read_text())
        access = acl["luci-app-online-upgrade"]
        self.assertEqual(access["read"], {"ubus": {"luci.swrt_upgrade": ["status"]}})
        self.assertEqual(set(access["write"]["ubus"]["luci.swrt_upgrade"]),
                         {"check", "download", "install", "set_source", "set_channel"})
        self.assertNotIn("file", access["write"])

    def test_proxy_is_factory_default_and_source_is_preserved_as_configuration(self):
        self.assertIn("option source 'proxy'", (PACKAGE / "etc/config/swrt_upgrade").read_text())
        recipe = (PACKAGE.parent / "Makefile").read_text()
        self.assertIn("Package/luci-app-online-upgrade/conffiles", recipe)
        self.assertIn("/etc/config/swrt_upgrade", recipe)


@unittest.skipIf(os.name == "nt", "Real ash-compatible worker/lock tests run on Linux CI")
class OnlineUpgradeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in ("etc", "proc", "sbin", "bin", "tmp/sysinfo", "fixtures"):
            (self.root / name).mkdir(parents=True)
        self.identity = self.root / "etc/photonicat-release.json"
        self.identity.write_text(json.dumps({"repository": REPO, "board": "ariaboard,photonicat", "version": "photonicat1-20261101-120000-9"}))
        self.board = self.root / "tmp/sysinfo/board_name"
        self.board.write_text("ariaboard,photonicat\n")
        self.mounts = self.root / "proc/mounts"
        self.mounts.write_text("/dev/root /rom squashfs ro 0 0\noverlay / overlay rw 0 0\n")
        self.name = "photonicat-wrt-25.12-snapshot-r0-3682a14d-rockchip-armv8-ariaboard_photonicat-squashfs-sysupgrade_2026110223.img.gz"
        # Real gzip with a fwtool-style trailing metadata record; no gzip -t rejection.
        self.image = gzip.compress(b"fixture image") + b' {"supported_devices":["ariaboard,photonicat"]} FWx0'
        self.sha = hashlib.sha256(self.image).hexdigest()
        self.fixture = self.root / "fixtures"
        (self.fixture / "image").write_bytes(self.image)
        (self.fixture / "sha256sums").write_text(self.sha + "  ./" + self.name + "\n")
        base = f"https://github.com/{REPO}/releases/download/photonicat1-20261102-222244-55/"
        self.release = {"tag_name": "photonicat1-20261102-222244-55", "draft": False, "prerelease": False,
                        "body": "中文发布说明", "published_at": "2026-10-24T00:00:00Z", "assets": [
            {"id": 1, "name": self.name, "size": len(self.image), "browser_download_url": base + self.name,
             "digest": "sha256:" + self.sha},
            {"id": 2, "name": "SHA256SUMS.txt", "browser_download_url": base + "SHA256SUMS.txt"}]}
        self.write_release()
        self.log = self.root / "sysupgrade.log"
        self.worker = self.root / "tmp/swrt-upgrade"
        self.state = self.worker / "state.json"
        self.make_program("bin/curl", '''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys, time
r=pathlib.Path(os.environ['SWRT_UPGRADE_ROOT']); args=sys.argv[1:]; url=args[-1]
with (r/'curl.log').open('a') as f: f.write(url+'\\n')
if (r/'network-fail').exists(): sys.exit(22)
target=pathlib.Path(args[args.index('-o')+1]); fixtures=r/'fixtures'
if 'api.github.com' in url: source=fixtures/'release.json'
elif url.endswith('/SHA256SUMS.txt'): source=fixtures/'sha256sums'
else:
    if (r/'download-delay').exists(): time.sleep(.6)
    source=fixtures/'image'
shutil.copyfile(source,target)
''')
        self.make_program("sbin/sysupgrade", '''#!/bin/sh
printf '%s\\n' "$*" >> "$SWRT_UPGRADE_ROOT/sysupgrade.log"
if [ "$1" = '-T' ]; then
    [ ! -f "$SWRT_UPGRADE_ROOT/incompatible" ] || exit 1
    [ ! -f "$SWRT_UPGRADE_ROOT/partition-change" ] || echo 'Partition layout has changed. Full image will be written.'
    exit 0
fi
# Model OpenWrt stage2 terminating the caller after accepting the image.
# This stub never invokes the host's real sysupgrade or any block writer.
if [ -f "$SWRT_UPGRADE_ROOT/upgrade-reject" ]; then
    exit 7
fi
if [ -f "$SWRT_UPGRADE_ROOT/handoff-signal" ]; then
    printf '%s\\n' "$PPID" > "$SWRT_UPGRADE_ROOT/handoff-pid"
    kill -TERM "$PPID"
    exit 0
fi
# NEVER call the machine's real sysupgrade. A test flash returns immediately.
exit 0
''')
        self.make_program("bin/ubus", '''#!/bin/sh
if [ -f "$SWRT_UPGRADE_ROOT/invalid-metadata" ]; then
    printf '{"valid":false,"allow_backup":false}\\n'
else
    printf '{"valid":true,"allow_backup":true}\\n'
fi
''')
        self.make_program("bin/uci", '''#!/usr/bin/env python3
import json, os, pathlib, re, sys
r=pathlib.Path(os.environ['SWRT_UPGRADE_ROOT']); args=sys.argv[1:]
config=r/'etc/config'; staging=r/'uci-default'
while args and args[0].startswith('-'):
    flag=args.pop(0)
    if flag in ('-c','-t'):
        value=pathlib.Path(args.pop(0))
        if flag=='-c': config=value
        else: staging=value
action,key=args[:2]; file=config/'swrt_upgrade'; delta=staging/'swrt_upgrade'
existing=dict(re.findall(r"option ([a-z_]+) '([^']*)'",file.read_text())) if file.exists() else {}
if action=='get':
    option=key.rsplit('.',1)[-1]
    if option not in existing: sys.exit(1)
    print(existing[option])
elif action=='set':
    staging.mkdir(parents=True,exist_ok=True)
    data=json.loads(delta.read_text()) if delta.exists() else existing
    setting,value=key.split('=',1)
    if setting.startswith('swrt_upgrade.main.'):
        data[setting.rsplit('.',1)[-1]]=value
    delta.write_text(json.dumps(data))
elif action=='commit':
    if (r/'uci-fail').exists(): sys.exit(1)
    data=json.loads(delta.read_text()); config.mkdir(parents=True,exist_ok=True)
    file.write_text("config settings 'main'\\n"+''.join("\\toption "+k+" '"+v+"'\\n" for k,v in data.items()))
    delta.unlink()
else: sys.exit(1)
''')
        self.env = {**os.environ, "SWRT_UPGRADE_ROOT": str(self.root), "SWRT_UPGRADE_SCRIPT": str(ENGINE),
                    "PATH": str(self.root / "bin") + ":" + os.environ["PATH"]}

    def make_program(self, name, source):
        path = self.root / name
        path.write_text(source)
        path.chmod(0o755)

    def write_release(self):
        (self.fixture / "release.json").write_text(json.dumps(self.release))

    def run_engine(self, mode, data=None):
        return subprocess.run(["/bin/sh", str(ENGINE), mode], env=self.env,
                              input=json.dumps(data) if data is not None else None,
                              capture_output=True, text=True, timeout=12)

    def assert_ok(self, mode, data=None):
        result = self.run_engine(mode, data)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        value = json.loads(result.stdout)
        self.assertTrue(value["ok"], value)
        return value

    def wait_worker(self):
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            data = json.loads(self.state.read_text())
            if data["phase"] in ("ready", "failed"):
                # Wait for EXIT trap/FD cleanup before the next request.
                subprocess.run(["flock", str(self.worker / "lock"), "true"], timeout=3, check=True)
                return data
            time.sleep(.03)
        self.fail("Worker timed out: " + (self.worker / "worker.log").read_text())

    def prepare(self):
        self.assert_ok("check")
        self.assert_ok("download")
        data = self.wait_worker()
        self.assertEqual(data["phase"], "ready", data)

    def test_numeric_rollover_and_download_never_flashes(self):
        checked = self.assert_ok("check")
        self.assertEqual(checked["current"], "photonicat1-20261101-120000-9")
        self.assertEqual(checked["release"]["version"], "photonicat1-20261102-222244-55")
        self.assert_ok("download")
        self.assertEqual(self.wait_worker()["phase"], "ready")
        status = self.assert_ok("status")
        self.assertEqual(status["release"]["sha256"], self.sha)
        self.assertEqual(status["downloaded_bytes"], len(self.image))
        self.assertTrue(all(line.startswith("-T ") for line in self.log.read_text().splitlines()))

    def test_prerelease_default_and_stable_channel_remain_distinct(self):
        self.release["prerelease"] = True
        self.write_release()
        checked = self.assert_ok("check")
        self.assertEqual(checked["channel"], "prerelease")
        self.assertTrue(checked["release"]["prerelease"])
        changed = self.assert_ok("set-channel", {"channel": "stable"})
        self.assertIsNone(changed["release"])
        self.assertNotEqual(self.run_engine("check").returncode, 0)
        self.release["prerelease"] = False
        self.write_release()
        self.assertEqual(self.assert_ok("check")["state"]["phase"], "available")
        self.assertTrue((self.root / "curl.log").read_text().splitlines()[-1].endswith("/latest"))

    def test_release_list_sorts_run_numbers_numerically(self):
        variants = []
        for run in (9, 10):
            item = json.loads(json.dumps(self.release))
            tag = f"photonicat1-20261102-222244-{run}"
            item["tag_name"] = tag
            item["prerelease"] = True
            for asset in item["assets"]:
                asset["browser_download_url"] = f"https://github.com/{REPO}/releases/download/{tag}/{asset['name']}"
            variants.append(item)
        (self.fixture / "release.json").write_text(json.dumps(list(reversed(variants))))
        checked = self.assert_ok("check")
        self.assertEqual(checked["release"]["tag"], "photonicat1-20261102-222244-10")

    def test_legacy_immutable_identity_is_read_as_data(self):
        self.identity.unlink()
        legacy = self.root / "rom/etc/online-upgrade-device"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("BUILD_TAG='photonicat1-20261101-120000-9'\n")
        self.assertEqual(self.assert_ok("check")["current"], "photonicat1-20261101-120000-9")
        legacy.write_text("BUILD_TAG='$(touch /tmp/should-never-run)'\n")
        self.assertNotEqual(self.run_engine("check").returncode, 0)

    def test_keep_default_and_channel_changes_preserve_source(self):
        self.assertTrue(self.assert_ok("status")["keep_default"])
        self.assert_ok("set-source", {"source": "github"})
        changed = self.assert_ok("set-channel", {"channel": "stable"})
        self.assertEqual(changed["source"], "github")
        self.assertEqual(self.assert_ok("status")["channel"], "stable")
        self.assert_ok("set-source", {"source": "proxy"})
        self.assertEqual(self.assert_ok("status")["channel"], "stable")

    def test_real_repository_release_schema_matches(self):
        fixture = ROOT / "scripts/tests/fixtures/photonicat-release.json"
        (self.fixture / "release.json").write_bytes(fixture.read_bytes())
        checked = self.assert_ok("check")
        self.assertEqual(checked["release"]["tag"], "photonicat1-20261102-222244-55")
        self.assertTrue(checked["release"]["prerelease"])
        self.assertIn("ariaboard_photonicat-squashfs-sysupgrade_", checked["release"]["name"])

    def test_proxy_covers_version_checksum_and_firmware_but_keeps_canonical_asset_identity(self):
        self.prepare()
        urls = (self.root / "curl.log").read_text().splitlines()
        self.assertEqual(len(urls), 4)
        self.assertTrue(all(url.startswith("https://gh-proxy.com/https://") for url in urls))
        self.assertIn("api.github.com", urls[0])
        self.assertTrue(urls[2].endswith("/SHA256SUMS.txt"))
        self.assertTrue(urls[3].endswith("/" + self.name))
        status = self.assert_ok("status")
        self.assertEqual(status["source"], "proxy")
        self.assertEqual(status["release"]["source"], "proxy")
        self.assertTrue(status["release"]["url"].startswith("https://github.com/"))

    def test_switch_source_persists_and_invalidates_old_ready_image(self):
        self.prepare()
        before = len((self.root / "curl.log").read_text().splitlines())
        changed = self.assert_ok("set-source", {"source": "github"})
        self.assertEqual(changed["source"], "github")
        self.assertEqual(changed["state"]["phase"], "idle")
        self.assertIsNone(changed["release"])
        self.assertFalse((self.worker / "firmware.img.gz").exists())
        self.assertEqual(self.assert_ok("status")["source"], "github")
        self.prepare()
        urls = (self.root / "curl.log").read_text().splitlines()[before:]
        self.assertEqual(len(urls), 4)
        self.assertTrue(all(url.startswith(("https://api.github.com/", "https://github.com/")) for url in urls))

    def test_invalid_source_never_discards_ready_firmware(self):
        self.prepare()
        for value in ("https://example.com", "proxy; reboot", "", None, []):
            self.assertNotEqual(self.run_engine("set-source", {"source": value}).returncode, 0)
            self.assertEqual(self.assert_ok("status")["state"]["phase"], "ready")
            self.assertTrue((self.worker / "firmware.img.gz").exists())

    def test_same_source_preserves_ready_image_and_commit_failure_keeps_old_source(self):
        self.prepare()
        self.assertEqual(self.assert_ok("set-source", {"source": "proxy"})["state"]["phase"], "ready")
        (self.root / "uci-fail").touch()
        self.assertNotEqual(self.run_engine("set-source", {"source": "github"}).returncode, 0)
        status = self.assert_ok("status")
        self.assertEqual(status["source"], "proxy")
        self.assertEqual(status["state"]["phase"], "ready")

    def test_source_change_outside_ui_requires_fresh_verification(self):
        self.prepare()
        config = self.root / "etc/config/swrt_upgrade"
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text("config settings 'main'\n\toption source 'github'\n")
        self.assert_ok("install", {"keep": 0, "sha256": self.sha})
        state = self.wait_worker()
        self.assertEqual(state["phase"], "failed")
        self.assertIn("更新源已变化", state["message"])
        self.assertTrue(all(line.startswith("-T ") for line in self.log.read_text().splitlines()))

    def test_installing_state_cannot_change_source(self):
        self.assert_ok("check")
        self.state.write_text('{"phase":"installing"}')
        self.assertNotEqual(self.run_engine("set-source", {"source": "github"}).returncode, 0)
        self.assertEqual(self.assert_ok("status")["source"], "proxy")

    def test_other_board_and_unidentified_firmware_never_download(self):
        for board, version in (("ariaboard,photonicat2", "photonicat1-20261101-120000-9"), ("ariaboard,photonicat", "")):
            with self.subTest(board=board, version=version):
                self.board.write_text(board)
                self.identity.write_text(json.dumps({"repository": REPO, "board": "ariaboard,photonicat", "version": version}))
                self.assertNotEqual(self.run_engine("check").returncode, 0)
                self.assertFalse((self.root / "curl.log").exists())

    def test_rom_identity_wins_over_preserved_etc_identity(self):
        rom = self.root / "rom/etc/photonicat-release.json"
        rom.parent.mkdir(parents=True)
        rom.write_text(self.identity.read_text())
        self.identity.write_text("{}")
        self.assertEqual(self.assert_ok("check")["current"], "photonicat1-20261101-120000-9")

    def test_filesystem_cannot_silently_switch(self):
        self.mounts.write_text("/dev/root / ext4 rw 0 0\n")
        self.assertNotEqual(self.run_engine("check").returncode, 0)
        self.assertFalse(self.log.exists())

    def test_drafts_missing_checksums_and_foreign_urls_rejected(self):
        original = json.loads(json.dumps(self.release))
        for kind in ("draft", "checksum", "url"):
            with self.subTest(kind=kind):
                self.release = json.loads(json.dumps(original))
                if kind in ("draft", "prerelease"): self.release[kind] = True
                elif kind == "checksum": self.release["assets"].pop()
                else: self.release["assets"][0]["browser_download_url"] = "https://example.com/image.img.gz"
                self.write_release()
                self.assertNotEqual(self.run_engine("check").returncode, 0)

    def test_same_or_older_release_cannot_be_reinstalled(self):
        for version in ("photonicat1-20261102-222244-55", "photonicat1-20261103-000000-56"):
            self.identity.write_text(json.dumps({"repository": REPO, "board": "ariaboard,photonicat", "version": version}))
            self.assertEqual(self.assert_ok("check")["state"]["phase"], "current")
            self.assertNotEqual(self.run_engine("download").returncode, 0)

    def test_corrupted_download_is_removed_and_never_validated_or_flashed(self):
        self.assert_ok("check")
        (self.fixture / "image").write_bytes(b"x" * len(self.image))
        self.assert_ok("download")
        self.assertEqual(self.wait_worker()["phase"], "failed")
        self.assertFalse((self.worker / "firmware.img.gz").exists())
        self.assertFalse(self.log.exists())

    def test_partition_change_and_platform_rejection_block_ready(self):
        for kind in ("partition-change", "incompatible", "invalid-metadata"):
            with self.subTest(kind=kind):
                flag = self.root / kind
                flag.touch()
                self.assert_ok("check")
                self.assert_ok("download")
                self.assertEqual(self.wait_worker()["phase"], "failed")
                flag.unlink()

    def test_asset_replacement_after_check_is_rejected(self):
        self.assert_ok("check")
        self.release["assets"][0]["id"] = 99
        self.write_release()
        self.assert_ok("download")
        self.assertEqual(self.wait_worker()["phase"], "failed")
        self.assertFalse(self.log.exists())

    def test_duplicate_checksum_entries_and_network_errors_fail_closed(self):
        self.assert_ok("check")
        checksums = self.fixture / "sha256sums"
        checksums.write_text(checksums.read_text() * 2)
        self.assert_ok("download")
        self.assertEqual(self.wait_worker()["phase"], "failed")
        self.assertFalse(self.log.exists())
        (self.root / "network-fail").touch()
        self.assertNotEqual(self.run_engine("check").returncode, 0)
        self.assertEqual(self.assert_ok("status")["state"]["phase"], "failed")

    def test_tampering_after_ready_is_rechecked_before_flash(self):
        self.prepare()
        (self.worker / "firmware.img.gz").write_bytes(b"x" * len(self.image))
        self.assert_ok("install", {"keep": 0, "sha256": self.sha})
        self.assertEqual(self.wait_worker()["phase"], "failed")
        self.assertTrue(all(line.startswith("-T ") for line in self.log.read_text().splitlines()))

    def test_install_requires_confirmed_digest_and_passes_no_force_flags(self):
        self.prepare()
        self.assertNotEqual(self.run_engine("install", {"keep": 0, "sha256": "0" * 64}).returncode, 0)
        self.prepare()
        self.assert_ok("install", {"keep": 0, "sha256": self.sha})
        # Test stub returns from sysupgrade: this MUST show failure rather than success.
        self.assertEqual(self.wait_worker()["phase"], "failed")
        calls = self.log.read_text().splitlines()
        self.assertTrue(any(line.startswith("-n ") for line in calls))
        self.assertFalse(any("--force" in line or "-F " in line for line in calls))
        self.assertTrue((self.worker / 'firmware.img.gz').exists(),
                        'The handed-off image must survive even if sysupgrade returns unexpectedly')

    def test_stage2_termination_does_not_delete_accepted_firmware(self):
        self.prepare()
        (self.root / 'handoff-signal').touch()
        self.assert_ok('install', {'keep': 0, 'sha256': self.sha})
        deadline = time.monotonic() + 8
        while not (self.root / 'handoff-pid').exists() and time.monotonic() < deadline:
            time.sleep(.03)
        self.assertTrue((self.root / 'handoff-pid').exists(), 'Installer did not reach the handoff stub')
        # Wait until the caller and its stub have both released the inherited lock.
        subprocess.run(['flock', str(self.worker / 'lock'), 'true'], timeout=3, check=True)
        image = self.worker / 'firmware.img.gz'
        self.assertTrue(image.exists(), 'Stage2 needs this image after stopping the update worker')
        self.assertEqual(hashlib.sha256(image.read_bytes()).hexdigest(), self.sha)
        self.assertEqual(json.loads(self.state.read_text())['phase'], 'installing')
        calls = self.log.read_text().splitlines()
        self.assertEqual(len([line for line in calls if line.startswith('-n ')]), 1)

    def test_sysupgrade_rejection_reports_failure_and_retains_image(self):
        for keep in (0, 1):
            with self.subTest(keep=keep):
                self.prepare()
                (self.root / 'upgrade-reject').touch()
                self.assert_ok('install', {'keep': keep, 'sha256': self.sha})
                state = self.wait_worker()
                self.assertEqual(state['phase'], 'failed')
                self.assertIn('拒绝或中止请求', state['message'])
                self.assertEqual(hashlib.sha256((self.worker / 'firmware.img.gz').read_bytes()).hexdigest(), self.sha)
                (self.root / 'upgrade-reject').unlink()

    def test_simultaneous_download_and_stale_worker_recovery(self):
        self.assert_ok("check")
        (self.root / "download-delay").touch()
        self.assert_ok("download")
        self.assertNotEqual(self.run_engine("download").returncode, 0)
        self.assertNotEqual(self.run_engine("set-source", {"source": "github"}).returncode, 0)
        self.assertEqual(self.assert_ok("status")["source"], "proxy")
        self.assertEqual(self.wait_worker()["phase"], "ready")
        self.state.write_text('{"phase":"downloading"}')
        status = self.assert_ok("status")
        self.assertEqual(status["state"]["phase"], "failed")


if __name__ == "__main__":
    unittest.main()
