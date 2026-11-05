#!/bin/sh
# 仅为 FM350 自动 APN 增加补全入口；不写 UCI、不改变 PDP 编号及其他型号行为。
set -eu
. "$(dirname "$0")/../../scripts/lib/patch.sh"
feed=${1:?需要 QModem Feed 目录}
fragment="$(dirname "$0")/fm350-auto-apn.sh"
target="$feed/application/qmodem/files/usr/share/qmodem/fixes/fm350-auto-apn/auto-apn.sh"
test -s "$fragment" || pc_fail '缺少 FM350 自动 APN 片段'
sh -n "$fragment"
if [ -e "$target" ] && ! cmp -s "$fragment" "$target"; then
    pc_fail '已存在不同版本的 FM350 自动 APN 片段，请先核对'
fi
pc_init
pc_load "$feed/application/qmodem/files/usr/share/qmodem/modem_dial.sh"
pc_replace 'at_dial()
{' 'at_dial()
{
    . "${SCRIPT_DIR}/fixes/fm350-auto-apn/auto-apn.sh" # Pwrt-FM350-APN' 'FM350 自动 APN 拨号入口'
sh -n "$PC_WORK"
pc_commit
install -Dm644 "$fragment" "$target"
echo 'QModem：仅为 FM350 补全自动 APN，保留手填设置及现有 PDP 编号。'
