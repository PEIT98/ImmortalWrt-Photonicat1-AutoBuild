#!/bin/sh
# 将开机网卡等待和一次条件补扫接入官方 qmodem_init。
set -eu
. "$(dirname "$0")/../../scripts/lib/patch.sh"
feed=${1:?需要 QModem Feed 目录}
fragment="$(dirname "$0")/boot-scan.sh"
target="$feed/application/qmodem/files/usr/share/qmodem/fixes/boot-scan.sh"
test -s "$fragment" || pc_fail '缺少 QModem 开机扫描片段'
sh -n "$fragment"
if [ -e "$target" ] && ! cmp -s "$fragment" "$target"; then
    pc_fail '已存在不同版本的 QModem 开机扫描片段，请先核对'
fi
pc_init
pc_load "$feed/application/qmodem/files/etc/init.d/qmodem_init"
pc_replace '    #enabled by default' '    # Boot scans are scheduled once after the network devices settle.
    [ "${PWRT_QMODEM_BOOT_SCAN:-0}" -eq 1 ] && return 0

    #enabled by default' 'QModem 开机扫描去重入口'
pc_replace 'boot() {
    local delay=$(uci -q get qmodem.main.start_delay || echo 0)
    if [ "$delay" -gt 0 ]; then
        logger "Delay QModem Boot init scan for $delay S"
        ( sleep "$delay"; /usr/share/qmodem/modem_scan.sh scan >/dev/null 2>&1 ) &
    fi
    start
}' 'boot() {
    PWRT_QMODEM_BOOT_SCAN=1
    start
    unset PWRT_QMODEM_BOOT_SCAN
    config_load qmodem
    local block_auto_probe
    config_get block_auto_probe main block_auto_probe 0
    [ "$block_auto_probe" -eq 1 ] && return 0
    (
        . /usr/share/qmodem/fixes/boot-scan.sh
        pwrt_qmodem_boot_scan
    ) &
}' 'QModem 开机等待和条件补扫'
sh -n "$PC_WORK"
pc_commit
install -Dm644 "$fragment" "$target"
echo 'QModem：开机等待网卡稳定后全扫描，未识别时 15 秒后补扫一次。'
