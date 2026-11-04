#!/usr/bin/env python3
"""让通用 USB QMI 通过 netifd 发布 IPv4，并同步已协商的数据格式。"""

import argparse
from pathlib import Path


DIAL = Path("application/qmodem/files/usr/share/qmodem/modem_dial.sh")
CM = Path("application/quectel_CM_5G_M/src")
OWNER_CHECK = '''                { [ -x /usr/libexec/qmodem-host-ipv4-owner ] && /usr/libexec/qmodem-host-ipv4-owner "$modem_config"; }; then'''
OWNER_UPDATED = '''                { [ -x /usr/libexec/qmodem-host-ipv4-owner ] && /usr/libexec/qmodem-host-ipv4-owner "$modem_config"; } ||
                photonicat_netifd_owner; then'''
OWNER_FUNCTION = '''# photonicat-netifd-owner: only the generic USB QMI routed IPv4 path.
photonicat_netifd_owner()
{
    local owner sysroot root endpoint_driver
    [ "$driver" = qmi ] && [ "$bridge_enabled" != 1 ] || return 1
    [ "$pdp_type" != ipv6 ] || return 1
    owner=$(uci -q get "qmodem.$modem_config.host_ipv4_owner")
    [ -z "$owner" ] || return 1
    [ "$(uci -q get "qmodem.$modem_config.data_interface")" = usb ] || return 1
    sysroot="${QMODEM_SYSFS_ROOT:-/sys}"
    root="${PHOTONICAT_QMODEM_ROOT:-}"
    [ -n "$modem_netcard" ] || return 1
    endpoint_driver=$(basename "$(readlink -f "$sysroot/class/net/$modem_netcard/device/driver")")
    [ "$endpoint_driver" = qmi_wwan ] || return 1
    [ -r "$sysroot/class/net/$modem_netcard/qmi/raw_ip" ] || return 1
    [ -x "$root/usr/bin/quectel-CM-M" ] &&
        [ -x "$root/usr/libexec/qmodem-ipv4-event" ] &&
        [ -f "$root/lib/netifd/proto/qmodem_runtime.sh" ]
}

'''

FORMAT_OLD = '''        profile->rawIP = (le32_to_cpu(linkProto->Value) == 2);'''
FORMAT_NEW = '''        profile->qmi_data_format_valid = 1; /* photonicat-qmi-format */
        profile->rawIP = (le32_to_cpu(linkProto->Value) == 2);'''
FORMAT_SYNC = r'''/* photonicat-qmi-format: match generic qmi_wwan to the negotiated format.
 * Managed IPv4 bypasses the legacy DHCP-failure/raw-IP fallback below. */
static int photonicat_sync_qmi_format(PROFILE_T *profile, const char *ifname) {
    char path[128], mode, expected;
    int fd, was_up, failed = 0;
    if (!profile->managed_ipv4 || !profile->qmi_data_format_valid ||
        profile->request_ops != &qmi_request_ops || profile->qmap_mode ||
        profile->qmapnet_adapter[0] || profile->generic_mhi)
        return 0;
    snprintf(path, sizeof(path), "/sys/class/net/%s/qmi/raw_ip", ifname);
    fd = open(path, O_RDWR | O_NONBLOCK | O_NOCTTY);
    if (fd < 0) {
        if (errno == ENOENT) return 0; /* vendor drivers have no raw_ip node */
        dbg_time("Cannot open QMI data format for %s: %s", ifname, strerror(errno));
        return -1;
    }
    expected = profile->rawIP ? 'Y' : 'N';
    if (read(fd, &mode, 1) != 1) { close(fd); return -1; }
    if (mode == expected || mode == (profile->rawIP ? '1' : '0')) {
        close(fd);
        return 0;
    }
    if (mode != 'Y' && mode != 'N' && mode != '0' && mode != '1') {
        close(fd);
        return -1;
    }
    was_up = !!(ifc_get_flags(ifname) & IFF_UP);
    if (was_up) ifc_set_state(ifname, 0);
    if (lseek(fd, 0, SEEK_SET) < 0 || write(fd, &expected, 1) != 1 ||
        lseek(fd, 0, SEEK_SET) < 0 || read(fd, &mode, 1) != 1 || mode != expected)
        failed = 1;
    close(fd);
    if (was_up) ifc_set_state(ifname, 1);
    if (failed) {
        dbg_time("Cannot synchronize QMI data format for %s", ifname);
        return -1;
    }
    dbg_time("Synchronized QMI data format for %s: raw_ip=%c", ifname, expected);
    return 0;
}

'''
MANAGED_OLD = '''    if (profile->managed_ipv4) {
        publish_ipv4(profile, ifname, 1);'''
MANAGED_NEW = '''    if (profile->managed_ipv4) {
        if (photonicat_sync_qmi_format(profile, ifname)) {
            publish_ipv4(profile, ifname, 0);
            return;
        }
        publish_ipv4(profile, ifname, 1);'''


def replace_once(source, old, new, label):
    if source.count(new) == 1 and old not in source.replace(new, "", 1):
        return source
    if source.count(old) != 1 or new in source:
        raise ValueError(f"{label} 上游布局变化，请先核对源码")
    return source.replace(old, new, 1)


def patched_files(feed):
    paths = [DIAL, CM / "QMIThread.h", CM / "QMIThread.c", CM / "udhcpc.c"]
    original = {path: (feed / path).read_text() for path in paths}
    updated = dict(original)
    source = replace_once(original[DIAL], OWNER_CHECK, OWNER_UPDATED, "IPv4 接管条件")
    if OWNER_FUNCTION not in source:
        if "photonicat-netifd-owner:" in source:
            raise ValueError("IPv4 接管函数不完整，请核对源码")
        source = replace_once(source, "\ndial(){\n", "\n" + OWNER_FUNCTION + "dial(){\n", "拨号入口")
    updated[DIAL] = source
    header = CM / "QMIThread.h"
    updated[header] = replace_once(original[header], "    int rawIP;\n", "    int rawIP;\n    bool qmi_data_format_valid; /* photonicat-qmi-format */\n", "QMI 数据格式状态")
    thread = CM / "QMIThread.c"
    source = replace_once(original[thread], FORMAT_OLD, FORMAT_NEW, "QMI 协商结果")
    source = replace_once(source, "    qmap_settings.size = sizeof(qmap_settings);", "    profile->qmi_data_format_valid = 0; /* photonicat-qmi-format */\n    qmap_settings.size = sizeof(qmap_settings);", "QMI 协商初始化")
    updated[thread] = source
    dhcp = CM / "udhcpc.c"
    source = replace_once(original[dhcp], MANAGED_OLD, MANAGED_NEW, "netifd 事件发布")
    if FORMAT_SYNC not in source:
        if "photonicat-qmi-format:" in source:
            raise ValueError("QMI 格式同步函数不完整，请核对源码")
        source = replace_once(source, "static void publish_ipv4(PROFILE_T *profile, const char *ifname, int up) {", FORMAT_SYNC + "static void publish_ipv4(PROFILE_T *profile, const char *ifname, int up) {", "QMI 格式同步")
    updated[dhcp] = source
    return original, updated


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("feed", type=Path)
    args = parser.parse_args()
    try:
        # Validate every anchor before writing any source file.
        original, updated = patched_files(args.feed)
    except (OSError, ValueError) as exc:
        parser.exit(1, f"::error::{exc}\n")
    for path, content in updated.items():
        if original[path] != content:
            (args.feed / path).write_text(content)
    print("QModem：通用 USB QMI 默认由 netifd 接管 IPv4，并核对已协商的数据格式；保留其他拨号路径和显式设置。")


if __name__ == "__main__":
    main()
