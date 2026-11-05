#!/bin/sh
# 使用已存在的默认 WeeChat 提供者，避免虚拟包依赖循环。
set -eu
. "$(dirname "$0")/../../lib/patch.sh"
root=${1:?需要源码目录}
recipe="$root/feeds/luci/applications/luci-app-weechat/Makefile"
[ -f "$recipe" ] || { echo 'WeeChat frontend is absent; no provider patch needed'; exit 0; }
pc_init
pc_load "$recipe"
count=$(awk '{ s=$0; while(match(s,/(^|[[:space:]])\+weechat([[:space:]]|$)/)) { n++; s=substr(s,RSTART+RLENGTH-1) } } END {print n+0}' "$PC_WORK")
[ "$count" -gt 0 ] || { echo 'WeeChat already uses a concrete provider'; exit 0; }
[ "$count" -eq 1 ] && grep -Fq 'define Package/weechat-minimal' "$root/feeds/packages/net/weechat/Makefile" || pc_fail 'WeeChat provider layout changed; review before resolving dependencies'
pc_awk '{ if(match($0,/(^|[[:space:]])\+weechat([[:space:]]|$)/)) { p=RSTART; if(substr($0,p,1)!="+") p++; $0=substr($0,1,p-1) "+weechat-minimal" substr($0,p+8) } print }'
pc_commit
echo 'WeeChat: selected concrete default weechat-minimal provider'
