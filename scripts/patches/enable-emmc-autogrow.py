#!/usr/bin/env python3
"""Preserve expanded eMMC partitions in Rockchip validation AND upgrade paths.

Based on SlAlot/ImmortalWrt_Photonicat1 ae655185 (AGPL-3.0-only).
Validate the affected logic instead of pinning the hash of an entire upstream file.
"""
import hashlib
import json
from pathlib import Path
import re
import sys

RELATIVE = "target/linux/rockchip/armv8/base-files/lib/upgrade/platform.sh"


def prepare(root):
    root = Path(root)
    kernel = root / "target/linux/rockchip/armv8/config-6.12"
    kernel_config = kernel.read_text()
    for option in ("BLK_DEV_LOOP", "F2FS_FS"):
        if not re.search(rf"^CONFIG_{option}=y$", kernel_config, re.M):
            raise ValueError(f"CONFIG_{option} must be built in for preinit eMMC expansion")
    target = root / RELATIVE
    data = target.read_bytes()
    repo = Path(__file__).resolve().parents[2]
    helper = (repo / "patches/rockchip/swrt-upgrade-partitions.sh").read_bytes()
    audit = root / "photonicat-metadata/autogrow-upgrade.json"
    digest = lambda value: hashlib.sha256(value).hexdigest()
    if audit.exists():
        previous = json.loads(audit.read_text())
        if previous["helper_sha256"] != digest(helper) or previous["patched_sha256"] != digest(data):
            raise ValueError("Prepared partition upgrade logic changed; review before rebuilding")
        return
    text = data.decode()
    original = 'diff="$(grep -F -x -v -f /tmp/partmap.bootdisk /tmp/partmap.image)"'
    replacement = 'diff="$(swrt_partition_difference /tmp/partmap.bootdisk /tmp/partmap.image)"'
    # Each platform function must have its own native partition-map comparison.
    for name in ("platform_check_image", "platform_do_upgrade"):
        function = re.search(rf"^{name}\(\) \{{\n(.*?)^\}}", text, re.M | re.S)
        if not function or function[1].count(original) != 1:
            raise ValueError(f"Rockchip {name} changed; review expanded partition handling")
    if text.count(original) != 2 or "UPGRADE_OPT_SAVE_PARTITIONS" not in text:
        raise ValueError("Unexpected Rockchip partition comparison implementation")
    if "swrt_partition_difference" in text:
        raise ValueError("Another expanded-partition implementation is already present")
    result = helper + b"\n" + text.replace(original, replacement).encode()
    target.write_bytes(result)
    audit.parent.mkdir(parents=True, exist_ok=True)
    audit.write_text(json.dumps({
        "source_commit": "SlAlot/ImmortalWrt_Photonicat1@ae655185",
        "original_sha256": digest(data), "helper_sha256": digest(helper),
        "patched_sha256": digest(result), "preserve_expanded_root": True,
        "builtin_storage": ["BLK_DEV_LOOP", "F2FS_FS"],
    }, indent=2) + "\n")
    print("eMMC: expanded root partitions preserved in validation and upgrade paths")


if __name__ == "__main__":
    prepare(sys.argv[1])
