#!/usr/bin/env python3
"""先识别 QModem USB 网卡，再保留端口规则筛选 AT 串口。"""

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
LEGACY_PATCHED = (
    SERIAL
    + "\t\t\t/* photonicat-usb-net-scan: 白名单只筛选 AT 串口。 */\n"
    + "".join("\t" + line for line in GUARD.splitlines(keepends=True))
)
NETWORK_CONDITION = (
    '!strncmp(driver, "qmi_wwan", 8) || !strcmp(driver, "cdc_mbim") ||\n'
    '\t\t\t   strstr(driver, "cdc_ncm") || !strcmp(driver, "cdc_ether") ||\n'
    '\t\t\t   !strcmp(driver, "rndis_host")'
)
NETWORK_BODY = (
    "\t\t\tchar net_path[512];\n"
    '\t\t\tsnprintf(net_path, sizeof(net_path), "%s/net", path);\n'
    "\t\t\tlist_net_devices(net_path, &res->net_devices);\n"
)
NETWORK_TAIL = "\t\t} else if (" + NETWORK_CONDITION + ") {\n" + NETWORK_BODY + "\t\t}\n"
NETWORK_FIRST = (
    "\t\t/* photonicat-usb-net-first: 先收集网卡，再筛选 AT 串口。 */\n"
    + "\t\tif (" + NETWORK_CONDITION + ") {\n"
    + NETWORK_BODY
    + "\t\t\tcontinue;\n\t\t}\n"
)
PATH_LINE = '\t\tsnprintf(path, sizeof(path), "%s/%s", slot_path, de->d_name);\n'
SERIAL_END = "\t\t\tsl_free(&ttys);\n\t\t}\n"


def usb_scan_function(source: str) -> str:
    """只定位 USB 扫描函数，避免改动 PCIe、语音和其他路径。"""
    if source.count(START) != 1 or source.count(END) != 1:
        raise ValueError("QModem USB 扫描函数布局变化，请核对上游源码")
    start = source.index(START)
    end = source.index(END, start)
    return source[start:end]


def patch_source(source: str) -> str:
    original_body = usb_scan_function(source)
    body = original_body
    # 兼容本项目上一版补丁，更新后只保留一套网卡前置逻辑。
    if body.count(LEGACY_PATCHED) == 1:
        body = body.replace(LEGACY_PATCHED, ORIGINAL, 1)
    if "photonicat-usb-net-first" in body:
        if (
            body.count(PATH_LINE + NETWORK_FIRST) == 1
            and body.count(ORIGINAL) == 1
            and NETWORK_TAIL not in body
            and body.index(NETWORK_FIRST) < body.index(GUARD)
        ):
            return source
        raise ValueError("QModem 网卡前置补丁结构不完整，请核对源码")
    if (
        body.count(ORIGINAL) != 1
        or body.count(NETWORK_TAIL) != 1
        or body.count(PATH_LINE) != 1
        or "photonicat-usb-net-scan" in body
    ):
        raise ValueError("QModem 端口过滤逻辑变化，停止修改以保留上游功能")
    # 网卡分支先收集接口并直接 continue，不会再经过白名单检查。
    updated = body.replace(NETWORK_TAIL, "\t\t}\n", 1)
    updated = updated.replace(PATH_LINE, PATH_LINE + NETWORK_FIRST, 1)
    return source.replace(original_body, updated, 1)


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
    print("QModem：先收集 USB 网卡，再按原规则筛选 AT 串口；保留语音端口和动态模组配置。")


if __name__ == "__main__":
    main()
