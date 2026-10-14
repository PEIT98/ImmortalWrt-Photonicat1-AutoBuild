#!/usr/bin/env bash
# 功能：准备参考硬件配置、官方软件源、固件覆盖文件和内核补丁。
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


# iStore 官方软件中心。只引入软件包定义，随固件源码一起编译；
# 不使用在线安装脚本，也不替换 ImmortalWrt 的 APK 仓库。
if grep -Eq '^src-git istore ' "$SRC/feeds.conf.default"; then
  sed -i -E 's#^src-git istore .*#src-git istore https://github.com/linkease/istore;main#' "$SRC/feeds.conf.default"
else
  printf '\nsrc-git istore https://github.com/linkease/istore;main\n' >> "$SRC/feeds.conf.default"
fi

# 将项目内的 CPU 调频 LuCI 插件直接安装进 OpenWrt 本地软件包目录。
# 使用本地完整源码（含网页、菜单、rpcd ACL、简体中文翻译），而不是编译时修改 Feeds 插件。
# cpufreq 后端仍使用 ImmortalWrt 官方包；LuCI 构建规则仍取自官方 LuCI Feed。
CPUFREQ_SRC="$(cd "$(dirname "$0")/../.." && pwd)/packages/luci-app-cpufreq"
CPUFREQ_DST="$SRC/package/luci-app-cpufreq"
test -f "$CPUFREQ_SRC/Makefile" || { echo "::error::项目内缺少 luci-app-cpufreq 插件源码" >&2; exit 1; }
test ! -e "$CPUFREQ_DST" || { echo "::error::本地 luci-app-cpufreq 路径已被上游占用，禁止覆盖" >&2; exit 1; }
mkdir -p "$CPUFREQ_DST"
cp -a "$CPUFREQ_SRC/." "$CPUFREQ_DST/"
test -f "$CPUFREQ_DST/root/usr/share/rpcd/acl.d/luci-app-cpufreq.json"
test -f "$CPUFREQ_DST/htdocs/luci-static/resources/view/cpufreq.js"
test -f "$CPUFREQ_DST/po/zh_Hans/cpufreq.po"
grep -Fxq 'LUCI_DEPENDS:=+cpufreq' "$CPUFREQ_DST/Makefile"
grep -Fxq 'include $(TOPDIR)/feeds/luci/luci.mk' "$CPUFREQ_DST/Makefile"
echo 'CPU 调频管理：本地 luci-app-cpufreq（网页、ACL、中文翻译）已安装到源码树。'

# 不引入参考仓库的 Wi-Fi 密码、静态 USB0 拨号与其它网络预设。
mkdir -p "$SRC/files"
cp -a "$OVERLAY/." "$SRC/files/"

# 与 QModem 的动态接口命名解耦：不预设固定模组别名，只同步 mwan3 第三级 WAN。
QMODEM_MWAN_SYNC="$SRC/files/usr/bin/photonicat-qmodem-mwan3-sync"
QMODEM_MWAN_INIT="$SRC/files/etc/init.d/photonicat-qmodem-mwan3"
QMODEM_MWAN_HOTPLUG="$SRC/files/etc/hotplug.d/iface/95-photonicat-qmodem-mwan3"
QMODEM_MWAN_DEFAULT="$SRC/files/etc/uci-defaults/95-photonicat-qmodem-mwan3"
for file in "$QMODEM_MWAN_SYNC" "$QMODEM_MWAN_INIT" "$QMODEM_MWAN_HOTPLUG" "$QMODEM_MWAN_DEFAULT"; do
  test -f "$file" || { echo "::error::缺少 QModem 动态 mwan3 文件 $file" >&2; exit 1; }
  chmod 755 "$file"
  sh -n "$file"
done
grep -Fq 'modem_config' "$QMODEM_MWAN_SYNC" || exit 1
grep -Fq 'qmodem_priority3' "$QMODEM_MWAN_SYNC" || exit 1

# MyOpenWrt 的 tom_modem 权限文件直接放进固件根文件系统。
# rpcd 启动时会读取 acl.d，无须额外设置首启重启。
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

# 固件版本/存储卡片只使用 rootfs 覆盖文件；不能修改 Aurora 主题。
INFO_RPC="$SRC/files/usr/libexec/rpcd/luci.photonicat1"
DISK_CHECK="$SRC/files/usr/bin/photonicat-docker-storage-check"
test -f "$INFO_RPC" && test -f "$DISK_CHECK" || { echo "::error::光影猫信息卡片脚本缺失"; exit 1; }
chmod 755 "$INFO_RPC" "$DISK_CHECK"
sh -n "$INFO_RPC"
sh -n "$DISK_CHECK"
python3 -m json.tool "$SRC/files/usr/share/rpcd/acl.d/luci-photonicat1-info.json" >/dev/null
test -f "$SRC/files/www/luci-static/resources/view/status/include/99_photonicat1_info.js" || exit 1

# Bandix Plus 是多接口版本。只从上游源码提取两个 OpenWrt 包，
# 不将原版单网口 Bandix 的 eBPF/限速规则强加于设备。
BANDIX_TMP="$(mktemp -d)"
trap 'rm -rf "$BANDIX_TMP"' EXIT
git clone --quiet --depth 1 --branch main https://github.com/timsaya/openwrt-bandix-plus.git "$BANDIX_TMP/core"
git clone --quiet --depth 1 --branch main https://github.com/timsaya/luci-app-bandix-plus.git "$BANDIX_TMP/luci"
CORE_DST="$SRC/package/photonicat-bandix-plus"
LUCI_DST="$SRC/package/luci-app-bandix-plus"
mkdir -p "$CORE_DST" "$LUCI_DST"
cp -a "$BANDIX_TMP/core/openwrt-bandix-plus/." "$CORE_DST/"
cp -a "$BANDIX_TMP/luci/luci-app-bandix-plus/." "$LUCI_DST/"
test -f "$CORE_DST/Makefile" && test -f "$LUCI_DST/Makefile" || exit 1
# luci.mk infers LUCI_NAME/PKG_NAME from the folder name. The former
# package/photonicat-luci-app-bandix-plus registered an incorrect package name.
# Keep the actual luci-app-bandix-plus directory name to match config selection.
grep -Fq '# call BuildPackage' "$LUCI_DST/Makefile" || { echo "::error::Bandix LuCI Makefile 缺少包扫描标记" >&2; exit 1; }

# 官方默认启用 eBPF 流量服务。光影猫有 QModem/mwan3 多 WAN，
# 为避免首次启动改变数据转发，预置关闭；在 LuCI 配好接口后手动启用。
BANDIX_CONFIG="$CORE_DST/files/bandix_plus.config"
test -f "$BANDIX_CONFIG" || exit 1
if ! grep -Fq "option enable_traffic '1'" "$BANDIX_CONFIG"; then
  echo "::error::Bandix Plus 默认配置格式变化，请重新确认安全关闭开关" >&2
  exit 1
fi
sed -i "s/option enable_traffic '1'/option enable_traffic '0'/" "$BANDIX_CONFIG"
grep -Fq "option enable_traffic '0'" "$BANDIX_CONFIG" || exit 1
echo 'Bandix Plus 前/后端已加入：首次默认不启用流量挂钩和限速。'

# 西瓜皮原版 TD-TECH (3466) USB option 串口内核补丁（保持原内容不修改）。
# kmod-usb-serial-option 由 select-packages.py 选择；此处仅安装内核补丁源码。
# 必须确保 Rockchip 目标仍使用 Linux 6.12；如升级到新内核则明确报错，
# 避免补丁被放进错误目录而悄然失效。
TD_PATCH_SRC="$(dirname "$0")/../../999-add-TD-TECH-option-id.patch"
TD_PATCH_DIR="$SRC/target/linux/rockchip/patches-6.12"
test -f "$TD_PATCH_SRC" || { echo "::error::TD-TECH 补丁源文件丢失" >&2; exit 1; }
test -d "$TD_PATCH_DIR" || { echo "::error::Rockchip Linux 6.12 补丁目录不存在，需检查内核版本" >&2; exit 1; }
TD_PATCH_DEST="$TD_PATCH_DIR/999-add-TD-TECH-option-id.patch"
cp -f "$TD_PATCH_SRC" "$TD_PATCH_DEST"
cmp -s "$TD_PATCH_SRC" "$TD_PATCH_DEST" || { echo "::error::TD-TECH 补丁复制不一致" >&2; exit 1; }
grep -Fq 'TDTECH_VENDOR_ID' "$TD_PATCH_DEST" || { echo "::error::TD-TECH 补丁内容不完整" >&2; exit 1; }
echo 'TD-TECH 3466 USB 串口补丁已按西瓜皮原版加入 Rockchip Linux 6.12。'

# 参考西瓜皮的 Wi-Fi band_order 兼容调整：保留固件上游源码，最小替换频段顺序。
bash "$(dirname "$0")/../patches/wifi-band-order.sh" "$SRC"
echo '准备完成：已加载光影猫硬件配置、QModem stable 与 OpenClash 源（插件选择在 feeds 安装后进行）'
echo '已排除旧 ModemBand、旧短信、PassWall、SmartDNS、ZeroTier'
echo '首次使用：QModem 扫描拨号即可，无需固定别名；mwan3 自动识别实际 IPv4 接口，Wi-Fi STA 绑定 wwan'
