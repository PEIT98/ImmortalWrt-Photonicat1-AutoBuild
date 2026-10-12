#!/usr/bin/env bash
set -euo pipefail
REF="${1:?缺少光影猫参考仓库路径}"
SRC="${2:?缺少 ImmortalWrt 源码路径}"
OVERLAY="${3:?缺少项目 files 覆盖目录}"
test -f "$REF/.config"
test -f "$REF/feeds.conf.default"
test -f "$SRC/Makefile"
cp -f "$REF/.config" "$SRC/.config"
cp -f "$REF/feeds.conf.default" "$SRC/feeds.conf.default"

# QModem 官方 feed，每次从 stable 分支获取源码。
# 不论参考配置之前指定了哪个分支，都统一固定到 stable。
if grep -Eq '^src-git qmodem ' "$SRC/feeds.conf.default"; then
  sed -i -E 's#^src-git qmodem .*#src-git qmodem https://github.com/FUjr/QModem.git;stable#' "$SRC/feeds.conf.default"
else
  printf '\nsrc-git qmodem https://github.com/FUjr/QModem.git;stable\n' >> "$SRC/feeds.conf.default"
fi


# OpenClash 官方维护的 Mihomo/Clash LuCI 软件源。
if grep -Eq '^src-git openclash ' "$SRC/feeds.conf.default"; then
  sed -i -E 's#^src-git openclash .*#src-git openclash https://github.com/vernesong/OpenClash.git;master#' "$SRC/feeds.conf.default"
else
  printf '\nsrc-git openclash https://github.com/vernesong/OpenClash.git;master\n' >> "$SRC/feeds.conf.default"
fi

# 不引入参考仓库的 Wi-Fi 密码、静态 USB0 拨号与其它网络预设。
mkdir -p "$SRC/files"
cp -a "$OVERLAY/." "$SRC/files/"

# MyOpenWrt tom_modem ACL is shipped directly in the firmware rootfs overlay.
# rpcd reads /usr/share/rpcd/acl.d/*.json on startup; no first-boot restart needed.
TOM_ACL="$SRC/files/usr/share/rpcd/acl.d/tom_modem.json"
test -f "$TOM_ACL" || { echo "::error::缺少 MyOpenWrt tom_modem ACL 文件" >&2; exit 1; }
python3 -m json.tool "$TOM_ACL" >/dev/null
echo "MyOpenWrt ACL 已内置并通过 JSON 校验：/usr/share/rpcd/acl.d/tom_modem.json"

# Aurora 官方源码根目录直接包含 Makefile，直接作为 OpenWrt 本地软件包编译。
# 该软件包含自身的 UCI 首启默认主题设置，无须添加重复脚本。
THEME_DIR="$SRC/package/luci-theme-aurora"
if [ ! -f "$THEME_DIR/Makefile" ]; then
  git clone --depth=1 --branch master https://github.com/eamonxg/luci-theme-aurora.git "$THEME_DIR"
fi
[ -f "$THEME_DIR/Makefile" ] || { echo 'Aurora Makefile 不存在' >&2; exit 1; }

# 参考西瓜皮的 Wi-Fi band_order 兼容调整：保留固件上游源码，最小替换频段顺序。
bash "$(dirname "$0")/wifi-band-order.sh" "$SRC"
echo '准备完成：已加载光影猫硬件配置、QModem stable 与 OpenClash 源（插件选择在 feeds 安装后进行）'
echo '已排除旧 ModemBand、旧短信、PassWall、SmartDNS、ZeroTier'
echo '首次使用：QModem 模组别名设置 wwan_5g，Wi-Fi STA 绑定 wwan'
