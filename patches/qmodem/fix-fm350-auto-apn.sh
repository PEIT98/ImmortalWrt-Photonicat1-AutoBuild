#!/bin/sh
# Install FM350-only automatic APN lookup at the start of QModem AT dial.
set -eu
. "$(dirname "$0")/../../scripts/lib/patch.sh"
feed=${1:?需要 QModem Feed 目录}
fragment="$(dirname "$0")/fm350-auto-apn.sh"
target="$feed/application/qmodem/files/usr/share/qmodem/fixes/fm350-auto-apn.sh"
test -s "$fragment" || pc_fail '缺少 FM350 自动 APN 片段'
sh -n "$fragment"
if [ -e "$target" ] && ! cmp -s "$fragment" "$target"; then
    pc_fail '已存在不同版本的 FM350 自动 APN 片段，请先核对'
fi
pc_init
pc_load "$feed/application/qmodem/files/usr/share/qmodem/modem_dial.sh"
pc_require 'at_dial()'
pc_replace 'at_dial()
{
    if [ -z "$pdp_type" ];then' 'at_dial()
{
    . /usr/share/qmodem/fixes/fm350-auto-apn.sh # Pwrt-FM350-APN
    pwrt_fm350_auto_apn
    if [ -z "$pdp_type" ];then' 'FM350 自动 APN 拨号入口'
sh -n "$PC_WORK"
pc_commit
install -Dm644 "$fragment" "$target"
echo 'QModem：只为 FM350 在自动 APN 模式读取当前 PDP 的 APN。'
