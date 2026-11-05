#!/bin/sh
# QM 计时、启动扫描及 FM350 自动 APN 修复的统一构建入口。
set -eu
directory=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
feed=${1:?需要 QModem Feed 目录}
sh "$directory/fix-qmodem-monotonic-clock.sh" "$feed"
sh "$directory/fix-qmodem-boot-scan.sh" "$feed"
sh "$directory/fix-fm350-auto-apn.sh" "$feed"
