#!/bin/sh
# 构建主机脚本：先校验，再提交全部文本修改。
set -eu
. "$(dirname "$0")/../lib/patch.sh"
pc_init
pc_load "${1:?需要 QModem Feed 目录}/application/qmodem/files/etc/init.d/qmodem_init"
pc_replace 'boot() {
    local delay=$(uci -q get qmodem.main.start_delay || echo 0)
    if [ "$delay" -gt 0 ]; then
        logger "Delay QModem Boot init scan for $delay S"
        ( sleep "$delay"; /usr/share/qmodem/modem_scan.sh scan >/dev/null 2>&1 ) &
    fi
    start
}' 'boot() {
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
}' 'QModem boot 补扫'
pc_commit
printf "%s\n" "QModem：延时补扫遵从 USB/PCIe 扫描开关。"
