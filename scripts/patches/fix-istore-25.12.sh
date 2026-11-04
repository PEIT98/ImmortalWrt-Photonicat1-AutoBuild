#!/bin/sh
# 功能：兼容 iStore 在 ImmortalWrt 25.12 中的包名和依赖。
# 修正官方 LinkEase iStore 在 ImmortalWrt 25.12 中的软件包名称。
# 在安装 Feeds 后执行；仅修改编译机的临时源码。
set -eu
. "$(dirname "$0")/../lib/patch.sh"
SRC="${1:?用法: fix-istore-25.12.sh IMMORTALWRT_SRC}"
APP="$SRC/package/feeds/istore/luci-app-store/Makefile"
for pkg in luci-app-store luci-lib-taskd luci-lib-xterm taskd; do
  test -f "$SRC/package/feeds/istore/$pkg/Makefile" || {
    echo "::error::iStore feed 未正确注册 $pkg 的 Makefile" >&2
    exit 1
  }
done
pc_init
pc_load "$APP"
pc_require '# call BuildPackage' 1 'iStore Makefile 缺少或重复 OpenWrt package 扫描标记'
# luci.mk uses $(notdir $(CURDIR)) unless LUCI_NAME is set. Avoid feed-layout
# dependent package identity, so CONFIG_PACKAGE_luci-app-store is generated.
pc_awk '
/^[[:space:]]*(LUCI_NAME|PKG_NAME)[[:space:]]*[:?+]?=/ {
  key=$0; sub(/^[[:space:]]*/,"",key); sub(/[[:space:]]*[:?+]?=.*/,"",key)
  value=$0; sub(/^[^=]*=[[:space:]]*/,"",value)
  sub(/[[:space:]]+#.*$/,"",value); sub(/[[:space:]]*$/,"",value)
  if(++names[key]!=1 || value!="luci-app-store") bad=1
  next
}
/^include[[:space:]]+\$\(TOPDIR\)\/rules\.mk[[:space:]]*(#.*)?$/ {
  includes++; print; print "LUCI_NAME:=luci-app-store"; print "PKG_NAME:=luci-app-store"; next
}
{print}
END {
  if(includes!=1 || bad) {
    print "iStore 包名定义冲突或上游结构变化" > "/dev/stderr"
    exit 1
  }
}'
grep -Fxq 'LUCI_NAME:=luci-app-store' "$PC_WORK"
grep -Fxq 'PKG_NAME:=luci-app-store' "$PC_WORK"
pc_commit
echo 'iStore 官方来源保持不变；已显式修正 LuCI app 包名并确认 taskd 相关文件。'
