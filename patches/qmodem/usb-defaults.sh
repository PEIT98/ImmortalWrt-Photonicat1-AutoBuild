#!/bin/sh
# 首启应用西瓜皮的扫描延时与 AT 工具设置；光影猫模组仅使用 USB。
set -eu
uci -q get qmodem.main >/dev/null || exit 1
uci set qmodem.main.start_delay='15'
uci set qmodem.main.enable_usb_scan='1'
uci set qmodem.main.enable_pcie_scan='0'
uci set qmodem.main.try_preset_pcie='0'
uci set qmodem.main.at_tool='1'

# 西瓜皮原版兼容例外：MT5700 使用 tom_modem，不关闭 QM 拨号。
if lsusb 2>/dev/null | grep -qi '3466:3301'; then
    uci -q delete qmodem.main.at_tool
fi
uci commit qmodem
exit 0
