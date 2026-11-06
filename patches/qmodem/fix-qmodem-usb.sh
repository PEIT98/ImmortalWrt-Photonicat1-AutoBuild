#!/bin/sh
# 沿用西瓜皮的原生延时扫描和 AT 工具设置，自动扫描仅处理 USB 模组。
set -eu
. "$(dirname "$0")/../../scripts/lib/patch.sh"
feed=${1:?需要 QModem Feed 目录}
defaults="$(dirname "$0")/usb-defaults.sh"
target="$feed/application/qmodem/files/etc/uci-defaults/99-qmodem-usb"
test -s "$defaults" || pc_fail '缺少 QModem USB 默认配置'
sh -n "$defaults"
if [ -e "$target" ] && ! cmp -s "$defaults" "$target"; then
    pc_fail '已存在不同版本的 QModem USB 默认配置，请先核对'
fi
pc_init
pc_load "$feed/application/qmodem/files/etc/init.d/qmodem_init"
pc_require 'boot() {'
pc_replace '/usr/share/qmodem/modem_scan.sh scan >/dev/null 2>&1' \
    '/usr/share/qmodem/modem_scan.sh scan usb >/dev/null 2>&1' 'QModem 原生开机 USB 扫描入口'
sh -n "$PC_WORK"
pc_load "$feed/application/qmodem/files/etc/hotplug.d/net/20-modem-net"
pc_replace '[ -n "$slot_type" ] || exit
' '[ -n "$slot_type" ] || exit
# Photonicat1 modem slots carry USB only; leave PCIe Wi-Fi to its own driver.
[ "$slot_type" = usb ] || exit 0
' 'QModem 网卡热插拔 USB 范围'
sh -n "$PC_WORK"
pc_commit
install -Dm755 "$defaults" "$target"
echo 'QModem：原生 15 秒 USB 扫描，默认使用 sms_tool_q，TD-TECH 保留兼容例外。'
