#!/usr/bin/env bash
# 功能：只从 iStoreOS/LinkEase 官方源引入 QuickStart 首页与网口管理。
# 不覆盖默认网络，不替换 Aurora、QModem 和其他插件。
set -euo pipefail

SRC="${1:?用法: install-istore-quickstart.sh IMMORTALWRT_SRC}"
test -f "$SRC/Makefile" || { echo '::error::ImmortalWrt 路径不正确' >&2; exit 1; }
BACKEND_DST="$SRC/package/quickstart"
LUCI_DST="$SRC/package/luci-app-quickstart"
for dst in "$BACKEND_DST" "$LUCI_DST"; do
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    echo "::error::QuickStart 目标目录已存在，禁止覆盖：$dst" >&2
    exit 1
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git clone --quiet --depth 1 --branch master https://github.com/linkease/nas-packages.git "$TMP/nas"
git clone --quiet --depth 1 --branch main https://github.com/linkease/nas-packages-luci.git "$TMP/nas-luci"
BACKEND="$TMP/nas/network/services/quickstart"
LUCI="$TMP/nas-luci/luci/luci-app-quickstart"
test -f "$BACKEND/Makefile"
test -f "$BACKEND/files/quickstart.init"
test -f "$LUCI/Makefile"
test -f "$LUCI/luasrc/controller/quickstart.lua"
test -f "$LUCI/root/usr/share/luci/menu.d/luci-app-quickstart.json"
test -f "$LUCI/htdocs/luci-static/quickstart/index.js"
grep -Fq 'PKG_NAME:=quickstart' "$BACKEND/Makefile"
grep -Fq 'luci-app-store' "$LUCI/Makefile"
grep -Fq 'entry({"admin", "network", "interfaceconfig"}' "$LUCI/luasrc/controller/quickstart.lua" || {
  echo '::error::官方 QuickStart 网口配置入口已变更，停止集成' >&2
  exit 1
}
grep -Fq '"admin/quickstart/*"' "$LUCI/root/usr/share/luci/menu.d/luci-app-quickstart.json" || {
  echo '::error::官方 QuickStart 首页入口已变更，停止集成' >&2
  exit 1
}
# 原入口变化时停止构建，避免误改官方的其他页面。
for marker in \
  'entry({"admin", "network_guide"}, call("networkguide_index"), _("NetworkGuide"), 2)' \
  'entry({"admin", "nas", "raid"}, call("quickstart_index", {index={"admin", "nas"}}), _("RAID"), 10).leaf = true' \
  'entry({"admin", "nas", "smart"}, call("quickstart_index", {index={"admin", "nas"}}), _("S.M.A.R.T."), 11).leaf = true'; do
  grep -Fq "$marker" "$LUCI/luasrc/controller/quickstart.lua" || {
    echo "::error::QuickStart 菜单入口已变更：$marker" >&2
    exit 1
  }
done
grep -Fq '/devicemanagement' "$LUCI/htdocs/luci-static/quickstart/index.js" || {
  echo '::error::官方 QuickStart 局域网设备页面已变更，停止集成' >&2
  exit 1
}
grep -Fq '/lanctrl/listDevices/' "$LUCI/htdocs/luci-static/quickstart/index.js" || {
  echo '::error::官方 QuickStart 局域网设备接口已变更，停止集成' >&2
  exit 1
}
mkdir -p "$BACKEND_DST" "$LUCI_DST"
cp -a "$BACKEND/." "$BACKEND_DST/"
cp -a "$LUCI/." "$LUCI_DST/"

# 仅调整本地构建副本的菜单：隐藏网络向导，NAS 移入「服务」。
# 保留旧 NAS 和向导的无标题路由，避免官方首页内的链接失效。
awk '
  index($0, "entry({\"admin\", \"network_guide\"}, call(\"networkguide_index\"), _(\"NetworkGuide\"), 2)") {
    guide++
    print "        entry({\"admin\", \"network_guide\"}, call(\"networkguide_index\"))"
    next
  }
  index($0, "entry({\"admin\", \"nas\", \"raid\"}, call(\"quickstart_index\", {index={\"admin\", \"nas\"}}), _(\"RAID\"), 10).leaf = true") {
    raid++
    print "        entry({\"admin\", \"services\", \"nas\"}, firstchild(), _(\"NAS\"), 80)"
    print "        entry({\"admin\", \"services\", \"nas\", \"raid\"}, call(\"quickstart_index\", {index={\"admin\", \"services\", \"nas\"}}), _(\"RAID\"), 10).leaf = true"
    print "        entry({\"admin\", \"nas\", \"raid\"}, call(\"quickstart_index\", {index={\"admin\", \"nas\"}})).leaf = true"
    next
  }
  index($0, "entry({\"admin\", \"nas\", \"smart\"}, call(\"quickstart_index\", {index={\"admin\", \"nas\"}}), _(\"S.M.A.R.T.\"), 11).leaf = true") {
    smart++
    print "        entry({\"admin\", \"services\", \"nas\", \"smart\"}, call(\"quickstart_index\", {index={\"admin\", \"services\", \"nas\"}}), _(\"S.M.A.R.T.\"), 11).leaf = true"
    print "        entry({\"admin\", \"nas\", \"smart\"}, call(\"quickstart_index\", {index={\"admin\", \"nas\"}})).leaf = true"
    next
  }
  { print }
  END { if (guide != 1 || raid != 1 || smart != 1) exit 1 }
' "$LUCI_DST/luasrc/controller/quickstart.lua" > "$TMP/quickstart.controller.lua"
cp "$TMP/quickstart.controller.lua" "$LUCI_DST/luasrc/controller/quickstart.lua"
grep -Fq '"admin", "services", "nas", "raid"' "$LUCI_DST/luasrc/controller/quickstart.lua"
grep -Fq '"admin", "network", "interfaceconfig"' "$LUCI_DST/luasrc/controller/quickstart.lua"

# ImmortalWrt 25.12 的 LuCI 包名明确写死，仅改本地构建副本。
if grep -Eq '^(LUCI_NAME|PKG_NAME)[[:space:]]*[:?+]?=' "$LUCI_DST/Makefile"; then
  echo '::error::QuickStart 上游包名定义已变化，需重新检查' >&2
  exit 1
fi
awk '
  $0 == "include $(TOPDIR)/rules.mk" {
    n++
    print
    print "LUCI_NAME:=luci-app-quickstart"
    print "PKG_NAME:=luci-app-quickstart"
    next
  }
  { print }
  END { if (n != 1) exit 1 }
' "$LUCI_DST/Makefile" > "$TMP/quickstart.Makefile"
cp "$TMP/quickstart.Makefile" "$LUCI_DST/Makefile"
grep -Fxq 'LUCI_NAME:=luci-app-quickstart' "$LUCI_DST/Makefile"
grep -Fxq 'PKG_NAME:=luci-app-quickstart' "$LUCI_DST/Makefile"
echo "官方 iStoreOS QuickStart：首页与网口配置已就位"
echo "  nas-packages: $(git -C "$TMP/nas" rev-parse --short HEAD)"
echo "  nas-packages-luci: $(git -C "$TMP/nas-luci" rev-parse --short HEAD)"
