#!/usr/bin/env python3
"""让 QModem USB 网卡按驱动识别，端口白名单只筛选 AT 串口。"""

import argparse
from pathlib import Path


SCANNER = Path("application/modem_scan/src/modem_scand.c")
START = "static void scan_usb_slot("
END = "\nstatic void scan_associated_usb("
GUARD = (
    "\t\tif (!interface_allowed(&rule, if_port)) {\n"
    '\t\t\tlog_msg(LOG_L_DEBUG, "skip usb %s interface %s by modem_port_rule", slot, if_port);\n'
    "\t\t\tcontinue;\n"
    "\t\t}\n"
)
SERIAL = (
    '\t\tif (!strcmp(driver, "option") || !strcmp(driver, "cdc_acm") ||\n'
    '\t\t    !strcmp(driver, "qcserial") || !strcmp(driver, "usbserial_generic") ||\n'
    '\t\t    !strcmp(driver, "usbserial")) {\n'
)
ORIGINAL = GUARD + SERIAL
PATCHED = (
    SERIAL
    + "\t\t\t/* photonicat-usb-net-scan: 白名单只筛选 AT 串口。 */\n"
    + "".join("\t" + line for line in GUARD.splitlines(keepends=True))
)


def usb_scan_function(source: str) -> str:
    """只定位 USB 扫描函数，避免改动 PCIe、语音和其他路径。"""
    if source.count(START) != 1 or source.count(END) != 1:
        raise ValueError("QModem USB 扫描函数布局变化，请核对上游源码")
    start = source.index(START)
    end = source.index(END, start)
    return source[start:end]


def patch_source(source: str) -> str:
    body = usb_scan_function(source)
    if body.count(PATCHED) == 1 and ORIGINAL not in body:
        return source
    if body.count(ORIGINAL) != 1 or "photonicat-usb-net-scan" in body:
        raise ValueError("QModem 端口过滤逻辑变化，停止修改以保留上游功能")
    updated = body.replace(ORIGINAL, PATCHED, 1)
    return source.replace(body, updated, 1)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("feed", type=Path, help="已拉取的 QModem Feed 目录")
    args = parser.parse_args()
    path = args.feed / SCANNER
    try:
        original = path.read_text(encoding="utf-8")
        updated = patch_source(original)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"::error::{exc}\n")
    if updated != original:
        path.write_text(updated, encoding="utf-8")
    print("QModem：USB 网卡按驱动识别；保留 AT 白名单、语音端口和动态模组配置。")


if __name__ == "__main__":
    main()
