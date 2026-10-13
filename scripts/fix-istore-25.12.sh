#!/usr/bin/env bash
# Stabilize package names in the official LinkEase iStore feed on ImmortalWrt 25.12.
# Apply after scripts/feeds install; only changes GitHub runner source tree.
set -euo pipefail
SRC="${1:?用法: fix-istore-25.12.sh IMMORTALWRT_SRC}"
APP="$SRC/package/feeds/istore/luci-app-store/Makefile"
for pkg in luci-app-store luci-lib-taskd luci-lib-xterm taskd; do
  test -f "$SRC/package/feeds/istore/$pkg/Makefile" || {
    echo "::error::iStore feed 未正确注册 $pkg 的 Makefile" >&2
    exit 1
  }
done
grep -Fq '# call BuildPackage' "$APP" || {
  echo '::error::iStore Makefile 缺少 OpenWrt package 扫描标记' >&2
  exit 1
}
# luci.mk uses $(notdir $(CURDIR)) unless LUCI_NAME is set. Avoid feed-layout
# dependent package identity, so CONFIG_PACKAGE_luci-app-store is generated.
if ! grep -Eq '^LUCI_NAME[[:space:]]*[:?+]?=[[:space:]]*luci-app-store([[:space:]]|$)' "$APP"; then
  sed -i '/^include $(TOPDIR)\/rules.mk$/a LUCI_NAME:=luci-app-store' "$APP"
fi
if ! grep -Eq '^PKG_NAME[[:space:]]*[:?+]?=[[:space:]]*luci-app-store([[:space:]]|$)' "$APP"; then
  sed -i '/^LUCI_NAME:=luci-app-store$/a PKG_NAME:=luci-app-store' "$APP"
fi
grep -Fxq 'LUCI_NAME:=luci-app-store' "$APP"
grep -Fxq 'PKG_NAME:=luci-app-store' "$APP"
echo 'iStore 官方来源保持不变；已显式修正 LuCI app 包名并确认 taskd 相关文件。'
