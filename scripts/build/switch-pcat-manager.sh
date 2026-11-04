#!/bin/sh
# 只替换光影猫一代默认的 MCU 包。
set -eu
. "$(dirname "$0")/../lib/patch.sh"
pc_init
pc_load "${1:?需要 armv8.mk 路径}"
pc_awk '
/^define Device\/ariaboard_photonicat$/ { n++; inside=1 }
inside {
 line=$0
 if(index(line,"pcat-mgr")) { while((p=index(line,"pcat-mgr"))) { old++; line=substr(line,1,p-1) "luci-app-photonicat-power" substr(line,p+8) } }
 else if(index(line,"luci-app-photonicat-power")) new++
 print line
 if($0 ~ /^endef[[:space:]]*$/) { inside=0; closed++ }
 next
}
{print}
END { if(n!=1 || closed!=1 || !((old==1 && new==0) || (old==0 && new==1))) exit 1 }'
pc_commit
echo 'Photonicat1 默认 MCU 守护进程已并入 luci-app-photonicat-power'
