#!/usr/bin/env python3
"""使用隔离目录和模拟系统命令测试升级流程，绝不调用真机刷写。"""
from pathlib import Path
import copy
import fcntl
import gzip
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "online-upgrade/online-upgrade.sh"
REPO = "PEIT98/ImmortalWrt-Photonicat1-AutoBuild"
TAG = "photonicat1-20261017-080000-35"
OLD_TAG = "photonicat1-20261016-222022-34"
FILENAME = "immortalwrt-rockchip-armv8-ariaboard_photonicat-squashfs-sysupgrade_2026101708.img.gz"

MOCK = r'''
from pathlib import Path
import gzip,json,os,sys
root=Path(os.environ['ONLINE_UPGRADE_ROOT'])
name=Path(sys.argv[0]).name
args=sys.argv[1:]
state=json.loads((root/'scenario.json').read_text())
if name=='uci':
    args=[a for a in args if a!='-q']
    if args[0]=='get':
        key=args[1].split('.')[-1]
        if key not in state['config']:sys.exit(1)
        print(state['config'][key])
    sys.exit(0)
if name=='curl':
    url=args[-1]
    with (root/'curl.log').open('a') as log:log.write(url+'\n')
    out=Path(args[args.index('-o')+1])
    if 'api.github.com' in url:
        if state.get('api_failure'):sys.exit(22)
        out.write_text(json.dumps(state['releases']))
    elif url.endswith('SHA256SUMS.txt'):
        out.write_text(state['checksum'])
    elif state.get('bad_download') or (state.get('bad_proxy') and url.startswith('https://proxy.example/')):
        out.write_bytes(b'<html>mirror failed</html>')
    else:
        out.write_bytes((root/'payload.img.gz').read_bytes())
    sys.exit(0)
if name=='sysupgrade':
    with (root/'sysupgrade.log').open('a') as log:log.write(json.dumps(args)+'\n')
    if args[0]=='-T':sys.exit(1 if state.get('incompatible') else 0)
    if args[0]=='-b':
        if state.get('backup_failure'):sys.exit(1)
        Path(args[1]).write_bytes(gzip.compress(b'configuration fixture'))
    sys.exit(0)
sys.exit('unexpected mock command')
'''


class OnlineUpgradeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="photonicat-ota-test-")
        self.root = Path(self.temp.name)
        for folder in ("bin", "etc", "tmp/sysinfo", "root"):
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        for name in ("curl", "uci", "sysupgrade"):
            path = self.root / "bin" / name
            path.write_text("#!" + sys.executable + "\n" + MOCK)
            path.chmod(0o755)
        self.env = dict(os.environ, ONLINE_UPGRADE_ROOT=str(self.root), PATH=str(self.root / "bin") + ":" + os.environ["PATH"])
        (self.root / "tmp/sysinfo/board_name").write_text("ariaboard,photonicat\n")
        self.identity(OLD_TAG)
        payload = gzip.compress(b"photonicat firmware fixture")
        (self.root / "payload.img.gz").write_bytes(payload)
        digest = hashlib.sha256(payload).hexdigest()
        self.state = {
            "config": {"repo": REPO, "tag": "auto", "proxy": "https://proxy.example/", "keep_config": "1"},
            "releases": [{"tag_name": TAG, "draft": False, "prerelease": False, "published_at": "2026-10-17T00:00:00Z", "assets": [
                {"name": FILENAME, "size": len(payload), "digest": "sha256:" + digest, "browser_download_url": f"https://github.com/{REPO}/releases/download/{TAG}/{FILENAME}"},
                {"name": "SHA256SUMS.txt", "browser_download_url": f"https://github.com/{REPO}/releases/download/{TAG}/SHA256SUMS.txt"},
                {"name": "immortalwrt-x86-64-generic-squashfs-combined-efi.img.gz", "browser_download_url": "https://example.invalid/x86.img.gz"},
            ]}],
            "checksum": digest + "  ./" + FILENAME + "\n",
        }

    def tearDown(self):
        self.temp.cleanup()

    def identity(self, tag, rom=False):
        path = self.root / ("rom/etc/online-upgrade-device" if rom else "etc/online-upgrade-device")
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(f"DEVICE_BOARD='ariaboard,photonicat'\nBUILD_TAG='{tag}'\n")

    def run_update(self, mode="upgrade", success=True):
        (self.root / "scenario.json").write_text(json.dumps(self.state))
        result = subprocess.run(["sh", str(SCRIPT), mode], env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0 if success else 1, result.stdout + result.stderr)
        return result

    def commands(self):
        path = self.root / "sysupgrade.log"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    def urls(self):
        path = self.root / "curl.log"
        return path.read_text().splitlines() if path.exists() else []

    def test_check_only_never_downloads_or_flashes(self):
        result = self.run_update("check")
        self.assertIn("发现新固件", result.stdout)
        self.assertIn(FILENAME, result.stdout)
        self.assertEqual(len(self.urls()), 1)
        self.assertEqual(self.commands(), [])

    def test_upgrade_checks_image_and_backs_up_before_flash(self):
        self.run_update()
        calls = self.commands()
        self.assertEqual([c[0] for c in calls], ["-T", "-b", "-f"])
        self.assertNotIn("-F", sum(calls, []))
        self.assertTrue(list((self.root / "root").glob("pre-upgrade-backup-*.tar.gz")))

    def test_wrong_board_never_downloads(self):
        (self.root / "tmp/sysinfo/board_name").write_text("ariaboard,photonicat2\n")
        self.run_update(success=False)
        self.assertEqual(self.urls(), [])
        self.assertEqual(self.commands(), [])

    def test_bad_image_never_reaches_sysupgrade(self):
        self.state["bad_download"] = True
        self.run_update(success=False)
        self.assertEqual(self.commands(), [])

    def test_wrong_digest_never_reaches_sysupgrade(self):
        self.state["releases"][0]["assets"][0]["digest"] = "sha256:" + "0" * 64
        self.run_update(success=False)
        self.assertEqual(self.commands(), [])

    def test_bad_proxy_falls_back_to_original_url(self):
        self.state["bad_proxy"] = True
        self.run_update()
        firmware_urls = [u for u in self.urls() if u.endswith(".img.gz")]
        self.assertEqual(len(firmware_urls), 2)
        self.assertTrue(firmware_urls[0].startswith("https://proxy.example/"))
        self.assertTrue(firmware_urls[1].startswith("https://github.com/"))

    def test_same_release_does_not_flash_without_explicit_reinstall(self):
        self.identity(TAG)
        self.run_update()
        self.assertEqual(self.commands(), [])
        self.run_update("upgrade-force")
        self.assertEqual(self.commands()[-1][0], "-f")

    def test_immutable_identity_wins_over_old_overlay(self):
        self.identity(TAG, rom=True)
        self.run_update()
        self.assertEqual(self.commands(), [])

    def test_older_published_image_is_blocked_even_for_reinstall(self):
        self.identity("photonicat1-20261018-080000-36")
        self.run_update("upgrade-force", success=False)
        self.assertEqual(self.commands(), [])

    def test_no_fallback_to_other_device(self):
        del self.state["releases"][0]["assets"][0]
        self.run_update(success=False)
        self.assertEqual(self.commands(), [])

    def test_ambiguous_firmware_assets_are_rejected(self):
        duplicate = copy.deepcopy(self.state["releases"][0]["assets"][0])
        duplicate["name"] = duplicate["name"].replace("2026101708", "2026101709")
        self.state["releases"][0]["assets"].append(duplicate)
        self.run_update(success=False)
        self.assertEqual(self.commands(), [])

    def test_legacy_checksum_list_is_supported(self):
        self.state["releases"][0]["assets"][0].pop("digest")
        self.run_update()
        self.assertTrue(any(u.endswith("SHA256SUMS.txt") and u.startswith("https://github.com/") for u in self.urls()))

    def test_sysupgrade_rejection_blocks_backup_and_flash(self):
        self.state["incompatible"] = True
        self.run_update(success=False)
        self.assertEqual([c[0] for c in self.commands()], ["-T"])

    def test_backup_failure_blocks_flash(self):
        self.state["backup_failure"] = True
        self.run_update(success=False)
        self.assertEqual([c[0] for c in self.commands()], ["-T", "-b"])

    def test_discard_config_is_explicit_and_still_checks_image(self):
        self.state["config"]["keep_config"] = "0"
        self.run_update()
        self.assertEqual([c[0] for c in self.commands()], ["-T", "-n"])

    def test_api_failure_never_flashes(self):
        self.state["api_failure"] = True
        self.run_update(success=False)
        self.assertEqual(self.commands(), [])

    def test_concurrent_upgrade_cannot_start(self):
        with (self.root / "tmp/online-upgrade.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.run_update(success=False)
        self.assertEqual(self.commands(), [])

    def test_background_dispatch_preserves_lock_and_finishes(self):
        self.run_update("background")
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if self.commands() and self.commands()[-1][0] == "-f":
                break
            time.sleep(0.05)
        self.assertEqual([c[0] for c in self.commands()], ["-T", "-b", "-f"])


if __name__ == "__main__":
    unittest.main()
