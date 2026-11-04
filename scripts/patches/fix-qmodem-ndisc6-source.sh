#!/bin/sh
# 升级已知旧版 ndisc6；保留上游其他版本及校验已知旧补丁后才移除。
set -eu
. "$(dirname "$0")/../lib/patch.sh"
recipe=${1:?需要 ndisc6 Makefile}
pc_init
pc_load "$recipe"
managed=0
if grep -Fxq 'PKG_VERSION:=1.0.8' "$PC_WORK" &&
   grep -Fxq 'PKG_SOURCE_URL:=https://www.remlab.net/files/ndisc6' "$PC_WORK" &&
   grep -Fxq 'PKG_HASH:=1f2fb2dc1172770aa5a09d39738a44d8b753cc5e2e25e306ca78682f9fea0b4f' "$PC_WORK"; then
    managed=1
elif grep -Fxq 'PKG_VERSION:=1.0.2' "$PC_WORK"; then
    for line in 'PKG_NAME:=ndisc6' 'PKG_VERSION:=1.0.2' 'PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.bz2'; do
        pc_require "$line
" 1 'QModem ndisc6 1.0.2 包结构已变化'
    done
    pc_awk '
/^PKG_VERSION:=1\.0\.2$/ {v++; print "PKG_VERSION:=1.0.8"; next}
/^PKG_SOURCE_URL:=.+$/ {u++; print "PKG_SOURCE_URL:=https://www.remlab.net/files/ndisc6"; next}
/^(PKG_MD5SUM|PKG_HASH):=.+$/ {h++; print "PKG_HASH:=1f2fb2dc1172770aa5a09d39738a44d8b753cc5e2e25e306ca78682f9fea0b4f"; next}
{print}
END { if(v!=1 || u!=1 || h!=1) exit 1 }'
    managed=1
else
    grep -Fxq 'PKG_NAME:=ndisc6' "$PC_WORK" || pc_fail '上游 ndisc6 包定义已变化'
fi
if [ "$managed" -eq 1 ]; then
    for line in 'PKG_VERSION:=1.0.8' 'PKG_SOURCE_URL:=https://www.remlab.net/files/ndisc6' 'PKG_HASH:=1f2fb2dc1172770aa5a09d39738a44d8b753cc5e2e25e306ca78682f9fea0b4f'; do
        pc_require "$line
" 1 "ndisc6 下载定义重复或缺失"
    done
    pc_replace '	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/{rl,tcp}traceroute6 $(1)/usr/bin/
' '	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/rltraceroute6 $(PKG_INSTALL_DIR)/usr/bin/tcptraceroute6 $(1)/usr/bin/
' 'QModem traceroute6 安装定义'
    pc_replace 'TARGET_CFLAGS += -std=c99
' 'TARGET_CFLAGS += -std=gnu11
' 'QModem ndisc6 编译标准'
    while read -r name expected; do
        path="$(dirname "$recipe")/patches/$name"
        if [ -e "$path" ]; then
            [ "$(sha256sum "$path" | cut -d ' ' -f1)" = "$expected" ] || pc_fail "QModem $name 内容已变化，请检查补丁"
            printf '%s\n' "$path" >> "$PC_TMP/obsolete"
        fi
    done <<'HASHES'
100-favor_bsd.patch cda0e50a5ee800e1a3a4ef364c1b96ee4f95d595faa304fd6ddadcdaa9a95302
110-strverscmp.patch e45cb59f871a0b75b2554a8dfc431b9636f2d3354cea6c6c4912e7cf5a505678
HASHES
fi
pc_commit
if [ -f "$PC_TMP/obsolete" ]; then
    while IFS= read -r path; do rm -- "$path"; done < "$PC_TMP/obsolete"
fi
echo 'QModem ndisc6：源码、编译标准及旧补丁校验完成。'
