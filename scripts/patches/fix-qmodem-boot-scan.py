#!/usr/bin/env python3
"""使官方 QModem 延时补扫遵从 USB/PCIe 自动扫描开关。"""

import argparse
from pathlib import Path


ORIGINAL = '''boot() {
    local delay=$(uci -q get qmodem.main.start_delay || echo 0)
    if [ "$delay" -gt 0 ]; then
        logger "Delay QModem Boot init scan for $delay S"
        ( sleep "$delay"; /usr/share/qmodem/modem_scan.sh scan >/dev/null 2>&1 ) &
    fi
    start
}'''

UPDATED = '''boot() {
    local delay=$(uci -q get qmodem.main.start_delay || echo 0)
    # photonicat-boot-scan-switches: 补扫与后台自动扫描使用相同开关。
    local usb_scan=$(uci -q get qmodem.main.enable_usb_scan || echo 0)
    local pcie_scan=$(uci -q get qmodem.main.enable_pcie_scan || echo 0)
    local scan_type=
    case "$usb_scan:$pcie_scan" in
        1:1) scan_type=all ;;
        1:*) scan_type=usb ;;
        *:1) scan_type=pcie ;;
    esac
    if [ "$delay" -gt 0 ] && [ -n "$scan_type" ]; then
        logger "Delay QModem Boot init scan for $delay S ($scan_type)"
        ( sleep "$delay"; /usr/share/qmodem/modem_scan.sh scan "$scan_type" >/dev/null 2>&1 ) &
    fi
    start
}'''


def patch_source(source):
    if source.count(UPDATED) == 1 and ORIGINAL not in source:
        return source
    if source.count(ORIGINAL) != 1 or "photonicat-boot-scan-switches" in source:
        raise ValueError("QModem boot 补扫布局变化，请检查上游启动逻辑")
    return source.replace(ORIGINAL, UPDATED, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("feed", type=Path)
    args = parser.parse_args()
    path = args.feed / "application/qmodem/files/etc/init.d/qmodem_init"
    try:
        original = path.read_text()
        updated = patch_source(original)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"::error::{exc}\n")
    if updated != original:
        path.write_text(updated)
    print("QModem：延时补扫遵从 USB/PCIe 扫描开关；两个开关均关闭时不追加扫描。")


if __name__ == "__main__":
    main()
