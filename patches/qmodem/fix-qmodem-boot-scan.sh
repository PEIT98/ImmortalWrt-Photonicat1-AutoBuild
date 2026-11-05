#!/bin/sh
# 仅替换官方 USB 启动扫描入口；保留 PCIe、预扫描、热插拔及拨号配置。
set -eu
. "$(dirname "$0")/../../scripts/lib/patch.sh"
feed=${1:?需要 QModem Feed 目录}
fragment="$(dirname "$0")/boot-usb-scan.sh"
test -s "$fragment" || pc_fail '缺少 QM USB 启动扫描片段'
sh -n "$fragment"
pc_init
pc_load "$feed/application/qmodem/files/etc/init.d/qmodem_init"
body=$(cat "$fragment")
case "$(pc_count '_queue_ready_usb_scan()
{')" in
    0) ;;
    1) [ "$(pc_count "$body")" = 1 ] || pc_fail 'QM 已存在不同版本的启动扫描片段，停止重复插入' ;;
    *) pc_fail 'QM 启动扫描函数重复' ;;
esac
pc_replace '_scan_usb()
{
    _queue_boot_scan usb
}' '_scan_usb()
{
    _queue_ready_usb_scan
}' 'QModem USB 启动扫描入口'
pc_replace '_queue_boot_scan()
{' "$body

_queue_boot_scan()
{" 'QModem 启动扫描函数插入位置'
sh -n "$PC_WORK"
pc_commit
echo 'QModem：等待 USB 模组网卡就绪后扫描，15 秒后仍未识别才补扫一次。'
