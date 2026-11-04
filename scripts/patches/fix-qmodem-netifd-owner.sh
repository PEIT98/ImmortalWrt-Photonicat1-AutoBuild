#!/bin/sh
# 构建主机脚本：先校验，再提交全部文本修改。
set -eu
. "$(dirname "$0")/../lib/patch.sh"
feed=${1:?需要 QModem Feed 目录}
pc_init
pc_load "$feed/application/qmodem/files/usr/share/qmodem/modem_dial.sh"
pc_replace '                { [ -x /usr/libexec/qmodem-host-ipv4-owner ] && /usr/libexec/qmodem-host-ipv4-owner "$modem_config"; }; then' '                { [ -x /usr/libexec/qmodem-host-ipv4-owner ] && /usr/libexec/qmodem-host-ipv4-owner "$modem_config"; } ||
                photonicat_netifd_owner; then' 'IPv4 接管条件'
if [ "$(pc_count '# photonicat-netifd-owner: only the generic USB QMI routed IPv4 path.
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

')" -eq 0 ]; then
    [ "$(pc_count photonicat-netifd-owner:)" -eq 0 ] || pc_fail "IPv4 接管函数不完整"
pc_replace '
dial(){
' '
# photonicat-netifd-owner: only the generic USB QMI routed IPv4 path.
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

dial(){
' '拨号入口'
fi
pc_load "$feed/application/quectel_CM_5G_M/src/QMIThread.h"
pc_replace '    int rawIP;
' '    int rawIP;
    bool qmi_data_format_valid; /* photonicat-qmi-format */
' 'QMI 数据格式状态'
pc_load "$feed/application/quectel_CM_5G_M/src/QMIThread.c"
pc_replace '        profile->rawIP = (le32_to_cpu(linkProto->Value) == 2);' '        profile->qmi_data_format_valid = 1; /* photonicat-qmi-format */
        profile->rawIP = (le32_to_cpu(linkProto->Value) == 2);' 'QMI 协商结果'
pc_replace '    qmap_settings.size = sizeof(qmap_settings);' '    profile->qmi_data_format_valid = 0; /* photonicat-qmi-format */
    qmap_settings.size = sizeof(qmap_settings);' 'QMI 协商初始化'
pc_load "$feed/application/quectel_CM_5G_M/src/udhcpc.c"
pc_replace '    if (profile->managed_ipv4) {
        publish_ipv4(profile, ifname, 1);' '    if (profile->managed_ipv4) {
        if (photonicat_sync_qmi_format(profile, ifname)) {
            publish_ipv4(profile, ifname, 0);
            return;
        }
        publish_ipv4(profile, ifname, 1);' 'netifd 事件发布'
if [ "$(pc_count '/* photonicat-qmi-format: match generic qmi_wwan to the negotiated format.
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
    expected = profile->rawIP ? '"'"'Y'"'"' : '"'"'N'"'"';
    if (read(fd, &mode, 1) != 1) { close(fd); return -1; }
    if (mode == expected || mode == (profile->rawIP ? '"'"'1'"'"' : '"'"'0'"'"')) {
        close(fd);
        return 0;
    }
    if (mode != '"'"'Y'"'"' && mode != '"'"'N'"'"' && mode != '"'"'0'"'"' && mode != '"'"'1'"'"') {
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

')" -eq 0 ]; then
    [ "$(pc_count photonicat-qmi-format:)" -eq 0 ] || pc_fail "QMI 格式同步函数不完整"
pc_replace 'static void publish_ipv4(PROFILE_T *profile, const char *ifname, int up) {' '/* photonicat-qmi-format: match generic qmi_wwan to the negotiated format.
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
    expected = profile->rawIP ? '"'"'Y'"'"' : '"'"'N'"'"';
    if (read(fd, &mode, 1) != 1) { close(fd); return -1; }
    if (mode == expected || mode == (profile->rawIP ? '"'"'1'"'"' : '"'"'0'"'"')) {
        close(fd);
        return 0;
    }
    if (mode != '"'"'Y'"'"' && mode != '"'"'N'"'"' && mode != '"'"'0'"'"' && mode != '"'"'1'"'"') {
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

static void publish_ipv4(PROFILE_T *profile, const char *ifname, int up) {' 'QMI 格式同步'
fi
pc_commit
echo "QModem：通用 USB QMI 默认由 netifd 接管 IPv4，保留数据格式校验及显式设置。"
