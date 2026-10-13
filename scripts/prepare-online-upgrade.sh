#!/usr/bin/env bash
# Integrate hardened fork of gooyjq/luci-app-online-upgrade.
# Only validated backend can perform sysupgrade; unsafe CGI and auto-reinstall are excluded.
set -euo pipefail
SRC="$1"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_ROOT="$PROJECT_ROOT/scripts/online-upgrade"
PACKAGE="$SRC/package/luci-app-online-upgrade"
UPSTREAM_SHA="6f587f19d7f884ca89e4bfa95bbb9a002a521477"

test -f "$SRC/Makefile" || { echo "::error::ImmortalWrt source tree missing" >&2; exit 1; }
test ! -e "$PACKAGE" || { echo "::error::luci-app-online-upgrade package directory already exists" >&2; exit 1; }

mkdir -p "$PACKAGE"
git -C "$PACKAGE" init -q
git -C "$PACKAGE" remote add origin https://github.com/gooyjq/luci-app-online-upgrade.git
git -C "$PACKAGE" fetch -q --depth=1 origin "$UPSTREAM_SHA"
git -C "$PACKAGE" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
[ "$(git -C "$PACKAGE" rev-parse HEAD)" = "$UPSTREAM_SHA" ] || { echo "::error::upstream SHA mismatch" >&2; exit 1; }
test -f "$PACKAGE/LICENSE" || { echo "::error::upstream GPL license missing" >&2; exit 1; }

# Never copy upstream privileged CGI restore endpoint, automatic APK reinstall,
# auto-flash code, legacy Lua controller or first-boot settings.
rm -rf "$PACKAGE/root"
mkdir -p "$PACKAGE/root/usr/bin" \
         "$PACKAGE/root/etc/config" \
         "$PACKAGE/root/usr/share/luci/menu.d" \
         "$PACKAGE/root/usr/share/rpcd/acl.d" \
         "$PACKAGE/root/www/luci-static/resources/view/system"
cp "$PATCH_ROOT/Makefile" "$PACKAGE/Makefile"
cp "$PATCH_ROOT/check.sh" "$PACKAGE/root/usr/bin/online-upgrade.sh"
cp "$PATCH_ROOT/config" "$PACKAGE/root/etc/config/online-upgrade"
cp "$PATCH_ROOT/menu.json" "$PACKAGE/root/usr/share/luci/menu.d/luci-app-online-upgrade.json"
cp "$PATCH_ROOT/acl.json" "$PACKAGE/root/usr/share/rpcd/acl.d/luci-app-online-upgrade.json"
cp "$PATCH_ROOT/view.js" "$PACKAGE/root/www/luci-static/resources/view/system/online-upgrade.js"
chmod 755 "$PACKAGE/root/usr/bin/online-upgrade.sh"

sh -n "$PACKAGE/root/usr/bin/online-upgrade.sh"
python3 -m json.tool "$PACKAGE/root/usr/share/luci/menu.d/luci-app-online-upgrade.json" >/dev/null
python3 -m json.tool "$PACKAGE/root/usr/share/rpcd/acl.d/luci-app-online-upgrade.json" >/dev/null

test ! -e "$PACKAGE/root/www/cgi-bin/online-upgrade-restore"
test ! -e "$PACKAGE/root/etc/uci-defaults/90-online-upgrade-auto"
test ! -e "$PACKAGE/root/usr/lib/lua/luci/controller/admin_system/online_upgrade.lua"
grep -Fq '$(eval $(call BuildPackage,luci-app-online-upgrade))' "$PACKAGE/Makefile"
echo "Photonicat1 verified online upgrade integrated from pinned upstream $UPSTREAM_SHA; no unsafe CGI or auto APK install."
