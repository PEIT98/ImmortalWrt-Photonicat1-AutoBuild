#!/bin/sh
# 功能：兼容 iStore 在 ImmortalWrt 25.12 中的包名、依赖和下载顺序。
# 修正官方 LinkEase iStore 在 ImmortalWrt 25.12 中的软件包名称。
# 在安装 Feeds 后执行；仅修改编译机的临时源码。
set -eu
. "$(dirname "$0")/../../lib/patch.sh"
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

# iStore 原站优先，下载失败时仍保留官方镜像回退。
# 仅调整安装器重试顺序，不改 APK/OPKG 源及光影猫管理的源选择。
pc_load "$SRC/package/feeds/istore/luci-app-store/root/bin/is-opkg"
pc_replace 'do_in_mirrors() {
    local server
' 'do_in_mirrors() {
    local server result
    # Pwrt: try the origin before the iStore mirror.
    echo "Try origin server $FEEDS_SERVER"
    "$@" && return 0
    result=$?
' 'iStore 下载重试入口'
pc_replace '            PATH="$newpath" IS_ORIG_SERVER=$FEEDS_SERVER IS_MIRROR_SERVER=$server "$@" && return 0
' '            PATH="$newpath" IS_ORIG_SERVER=$FEEDS_SERVER IS_MIRROR_SERVER=$server "$@" && return 0
            result=$?
' 'iStore 镜像回退结果'
pc_replace '    echo "Try origin server $FEEDS_SERVER"
    "$@"
}' '    return "$result"
}' 'iStore 下载重试返回值'
sh -n "$PC_WORK"
pc_commit
echo 'iStore 包名和依赖已适配；下载优先原站、失败回退镜像，系统软件源设置保持不变。'
