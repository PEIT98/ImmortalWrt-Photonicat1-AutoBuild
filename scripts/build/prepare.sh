#!/usr/bin/env bash
# 功能：准备参考硬件配置、官方软件源、固件覆盖文件和内核补丁。
set -euo pipefail

# 子进程隔离补丁临时目录和退出清理，保留 prepare 自身的清理逻辑。
switch_pcat_manager() (
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
)

REF="${1:?缺少光影猫参考仓库路径}"
SRC="${2:?缺少 ImmortalWrt 源码路径}"
OVERLAY="${3:?缺少项目 files 覆盖目录}"
test -f "$REF/.config"
test -f "$REF/feeds.conf.default"
test -f "$SRC/Makefile"
cp -f "$REF/.config" "$SRC/.config"
cp -f "$REF/feeds.conf.default" "$SRC/feeds.conf.default"

# 官方 QModem main + PEIT98 自有 Generic main，构建时直接拉取。
# 保留官方 Next 界面；Generic 后续修复在自有复刻仓库维护。
if grep -Eq '^src-git qmodem ' "$SRC/feeds.conf.default"; then
  sed -i -E 's#^src-git qmodem .*#src-git qmodem https://github.com/FUjr/QModem.git;main#' "$SRC/feeds.conf.default"
else
  printf '\nsrc-git qmodem https://github.com/FUjr/QModem.git;main\n' >> "$SRC/feeds.conf.default"
fi

# Generic 从 PEIT98 复刻仓库拉取，交给 Feeds 递归扫描嵌套软件包。
if grep -Eq '^src-git qmodem_generic ' "$SRC/feeds.conf.default"; then
  sed -i -E 's#^src-git qmodem_generic .*#src-git qmodem_generic https://github.com/PEIT98/luci-app-qmodem-generic.git;main#' "$SRC/feeds.conf.default"
else
  printf '\nsrc-git qmodem_generic https://github.com/PEIT98/luci-app-qmodem-generic.git;main\n' >> "$SRC/feeds.conf.default"
fi

# 在线升级完整源码已放入项目插件目录，构建时直接复制，适配内容随项目维护。
ONLINE_SRC="$(cd "$(dirname "$0")/../.." && pwd)/packages/luci-app-online-upgrade"
ONLINE_DST="$SRC/package/luci-app-online-upgrade"
test -f "$ONLINE_SRC/Makefile" || { echo "::error::缺少项目内置 luci-app-online-upgrade" >&2; exit 1; }
test ! -e "$ONLINE_DST" || { echo "::error::在线升级目标路径已存在，禁止覆盖" >&2; exit 1; }
mkdir -p "$ONLINE_DST"
cp -a "$ONLINE_SRC/." "$ONLINE_DST/"
test -x "$ONLINE_DST/root/usr/libexec/swrt-upgrade"
test -f "$ONLINE_DST/root/www/luci-static/resources/view/system/swrt-upgrade.js"
test -f "$ONLINE_DST/root/usr/share/rpcd/acl.d/luci-app-online-upgrade.json"
echo '在线升级：SWRT 更新器已适配本仓库、日期标签与预发行通道。'

KEEPALIVE_SRC="$(cd "$(dirname "$0")/../.." && pwd)/packages/luci-app-swrt-disk-keepalive"
KEEPALIVE_DST="$SRC/package/luci-app-swrt-disk-keepalive"
test -f "$KEEPALIVE_SRC/Makefile"
test ! -e "$KEEPALIVE_DST" || { echo '::error::硬盘保活目标路径已存在，禁止覆盖' >&2; exit 1; }
mkdir -p "$KEEPALIVE_DST"
cp -a "$KEEPALIVE_SRC/." "$KEEPALIVE_DST/"
test -x "$KEEPALIVE_DST/root/usr/libexec/swrt-disk-keepalive"
echo '硬盘保活：已复制完整本地插件，首次默认关闭。'


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

# 单一软件包内含 MCU 服务、电源页面及右上角电池状态。
# 设备默认包同步替换，避免原 Go pcat-mgr 争用 /dev/ttyS4。
POWER_PACKAGE_SRC="$(cd "$(dirname "$0")/../.." && pwd)/packages/luci-app-photonicat-power"
POWER_PACKAGE_DST="$SRC/package/luci-app-photonicat-power"
test -f "$POWER_PACKAGE_SRC/Makefile" || { echo "::error::缺少 luci-app-photonicat-power 本地源码" >&2; exit 1; }
test ! -e "$POWER_PACKAGE_DST" || { echo "::error::电源管理目标路径被上游占用，禁止覆盖" >&2; exit 1; }
switch_pcat_manager "$SRC/target/linux/rockchip/image/armv8.mk"
mkdir -p "$POWER_PACKAGE_DST"
cp -a "$POWER_PACKAGE_SRC/." "$POWER_PACKAGE_DST/"
test -x "$POWER_PACKAGE_DST/files/pcat-manager.init"
test -f "$POWER_PACKAGE_DST/files/pcat-manager.conf"
test -f "$POWER_PACKAGE_DST/files/modem-manager-noop.c"
test -f "$POWER_PACKAGE_DST/files/patch-main.sh"
test -f "$POWER_PACKAGE_DST/files/patch-common.sh"
test -f "$POWER_PACKAGE_DST/files/patch-photonicat-ups.sh"
test -x "$POWER_PACKAGE_DST/files/98-photonicat-battery-language"
sh -n "$POWER_PACKAGE_DST/files/pcat-manager.init" "$POWER_PACKAGE_DST/files/98-photonicat-battery-language"
for patch in patch-common.sh patch-main.sh patch-photonicat-ups.sh; do
    sh -n "$POWER_PACKAGE_DST/files/$patch"
done
grep -Fq 'patch-photonicat-ups.sh' "$POWER_PACKAGE_DST/Makefile"
POWER_RPC="$POWER_PACKAGE_DST/root/usr/libexec/rpcd/luci.photonicat_power"
test -x "$POWER_RPC" || exit 1
test -x "$POWER_PACKAGE_DST/root/usr/libexec/rpcd/luci.battstatus" || exit 1
test -x "$POWER_PACKAGE_DST/root/usr/libexec/rpcd/luci.photonicat_header" || exit 1
sh -n "$POWER_RPC" "$POWER_PACKAGE_DST/root/usr/libexec/rpcd/luci.battstatus" "$POWER_PACKAGE_DST/root/usr/libexec/rpcd/luci.photonicat_header"
jq -e -s 'length == 1 and (.[0]|type) == "object"' "$POWER_PACKAGE_DST/root/usr/share/luci/menu.d/luci-app-photonicat-power.json" >/dev/null
jq -e -s 'length == 1 and (.[0]|type) == "object"' "$POWER_PACKAGE_DST/root/usr/share/rpcd/acl.d/luci-app-photonicat-power.json" >/dev/null
test -f "$POWER_PACKAGE_DST/htdocs/luci-static/resources/view/photonicat-power.js"
test -f "$POWER_PACKAGE_DST/htdocs/luci-static/resources/preload/battstatus.js"
test -f "$POWER_PACKAGE_DST/htdocs/luci-static/resources/photonicat-header.css"
test -f "$POWER_PACKAGE_DST/root/etc/config/luci_battstatus"
test -f "$POWER_PACKAGE_DST/root/etc/config/photonicat_packages"
test -x "$POWER_PACKAGE_DST/root/usr/libexec/photonicat-package-source"
test -x "$POWER_PACKAGE_DST/root/usr/libexec/rpcd/luci.photonicat_packages"
test -x "$POWER_PACKAGE_DST/files/99-photonicat-package-source"
test -f "$POWER_PACKAGE_DST/root/usr/share/photonicat/package-sources.awk"
for script in "$POWER_PACKAGE_DST/root/usr/libexec/photonicat-package-source" "$POWER_PACKAGE_DST/root/usr/libexec/rpcd/luci.photonicat_packages" "$POWER_PACKAGE_DST/files/99-photonicat-package-source"; do
    sh -n "$script"
done
test -f "$POWER_PACKAGE_DST/po/zh_Hans/battstatus.po"
grep -Fq 'luci.photonicat_power battery' "$POWER_PACKAGE_DST/root/usr/libexec/rpcd/luci.battstatus"
echo '光影猫管理：单一软件包提供 Aurora 设备状态、电池与电源页面及 PMU-only 后台。'

# 不引入参考仓库的 Wi-Fi 密码、静态 USB0 拨号与其它网络预设。
mkdir -p "$SRC/files"
cp -a "$OVERLAY/." "$SRC/files/"

# 在 preinit 挂载 overlay 前扩容；同时允许后续升级保留扩大的分区边界。
AUTOGROW="$SRC/files/usr/libexec/swrt-autogrow"
test -x "$AUTOGROW"
sh -n "$AUTOGROW" "$SRC/files/lib/preinit/79-swrt-autogrow"
sh "$(dirname "$0")/../patches/enable-emmc-autogrow.sh" "$SRC"

# Aurora 使用系统主机名显示品牌；默认配置在首启生成后应用。
BRAND_DEFAULT="$SRC/files/etc/uci-defaults/99-photonicat-brand"
test -f "$BRAND_DEFAULT"
chmod 755 "$BRAND_DEFAULT"
sh -n "$BRAND_DEFAULT"

# sysfixtime (START=00) 之后、网络与 QModem 服务之前校正过旧的系统时钟。
TIME_INIT="$SRC/files/etc/init.d/photonicat-time-floor"
TIME_LINK="$SRC/files/etc/rc.d/S01photonicat-time-floor"
test -f "$TIME_INIT"
test -L "$TIME_LINK"
test "$(readlink "$TIME_LINK")" = ../init.d/photonicat-time-floor
chmod 755 "$TIME_INIT"
sh -n "$TIME_INIT"

# 独立 LuCI 菜单覆盖：只改显示名称，不修改每次拉取的 QModem Feed。
MODEM_MENU="$SRC/files/usr/share/luci/menu.d/zz-photonicat-modem-title.json"
jq -e -s 'length == 1 and (.[0]|type) == "object"' "$MODEM_MENU" >/dev/null
grep -Fq '"title": "移动网络"' "$MODEM_MENU"

# 首启恢复旧项目的网络定制，保留管理地址、无线配置及网络工具。
NETWORK_DEFAULT="$SRC/files/etc/uci-defaults/99-photonicat-network"
test -f "$NETWORK_DEFAULT" || { echo '::error::缺少光影猫首启网络配置' >&2; exit 1; }
chmod 755 "$NETWORK_DEFAULT"
sh -n "$NETWORK_DEFAULT"
test ! -e "$SRC/files/usr/bin/photonicat-qmodem-mwan3-sync"
test ! -e "$SRC/files/usr/bin/photonicat-qmodem-scan"
echo 'QModem：使用官方扫描、串口识别和拨号默认值；mwan3 默认关闭。'

# MyOpenWrt 的 tom_modem 权限文件直接放进固件根文件系统。
# rpcd 启动时会读取 acl.d，无须额外设置首启重启。
TOM_ACL="$SRC/files/usr/share/rpcd/acl.d/tom_modem.json"
test -f "$TOM_ACL" || { echo "::error::缺少 MyOpenWrt tom_modem ACL 文件" >&2; exit 1; }
jq -e -s 'length == 1 and (.[0]|type) == "object"' "$TOM_ACL" >/dev/null
echo "MyOpenWrt ACL 已内置并通过 JSON 校验：/usr/share/rpcd/acl.d/tom_modem.json"

# Aurora 官方源码根目录直接包含 Makefile，直接作为 OpenWrt 本地软件包编译。
# 该软件包含自身的 UCI 首启默认主题设置，无须添加重复脚本。
THEME_DIR="$SRC/package/luci-theme-aurora"
if [ ! -f "$THEME_DIR/Makefile" ]; then
  git clone --depth=1 --branch master https://github.com/eamonxg/luci-theme-aurora.git "$THEME_DIR"
fi
[ -f "$THEME_DIR/Makefile" ] || { echo 'Aurora Makefile 不存在' >&2; exit 1; }

# Aurora 配套设置面板沿用主题作者的完整源码，直接作为单个本地包构建。
AURORA_CONFIG_DIR="$SRC/package/luci-app-aurora-config"
if [ ! -e "$AURORA_CONFIG_DIR" ]; then
  git clone --depth=1 --branch master https://github.com/eamonxg/luci-app-aurora-config.git "$AURORA_CONFIG_DIR"
fi
test -f "$AURORA_CONFIG_DIR/Makefile"
test -x "$AURORA_CONFIG_DIR/root/usr/libexec/rpcd/luci.aurora"
test -f "$AURORA_CONFIG_DIR/po/zh_Hans/aurora-config.po"
# 上游预生成的现代 JS 不适合旧 jsmin；保留上游关闭二次压缩的设置。
grep -Fxq 'LUCI_MINIFY_JS:=0' "$AURORA_CONFIG_DIR/Makefile"

# cake-autorate 使用固定稳定版源码和 SHA256，本地封装提供默认关闭的服务。
CAKE_SRC="$(cd "$(dirname "$0")/../.." && pwd)/packages/cake-autorate"
CAKE_DST="$SRC/package/cake-autorate"
test -f "$CAKE_SRC/Makefile" || { echo '::error::缺少 cake-autorate 本地封装' >&2; exit 1; }
test ! -e "$CAKE_DST" || { echo '::error::cake-autorate 目标路径已存在，禁止覆盖' >&2; exit 1; }
mkdir -p "$CAKE_DST"
cp -a "$CAKE_SRC/." "$CAKE_DST/"
test -x "$CAKE_DST/files/cake-autorate.init"
test -x "$CAKE_DST/files/cake-autorate-prepare"
test -x "$CAKE_DST/files/98-cake-autorate"
sh -n "$CAKE_DST/files/cake-autorate.init" "$CAKE_DST/files/cake-autorate-prepare" "$CAKE_DST/files/98-cake-autorate"
echo '文件管理和 Travelmate 使用官方包；Aurora 设置及 cake-autorate 已准备。'

# 固件版本/存储卡片只使用 rootfs 覆盖文件；不能修改 Aurora 主题。
INFO_RPC="$SRC/files/usr/libexec/rpcd/luci.photonicat1"
test -f "$INFO_RPC" || { echo "::error::光影猫信息卡片脚本缺失"; exit 1; }
chmod 755 "$INFO_RPC"
sh -n "$INFO_RPC"
jq -e -s 'length == 1 and (.[0]|type) == "object"' "$SRC/files/usr/share/rpcd/acl.d/luci-photonicat1-info.json" >/dev/null
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
# kmod-usb-serial-option 由 select-packages.sh 选择；此处仅安装内核补丁源码。
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

# 使用本次上游检测源码设置频段顺序、Photonicat SSID 和 WPA2 密码。
bash "$(dirname "$0")/../patches/wifi-band-order.sh" "$SRC"
echo '准备完成：已加载光影猫配置、官方 QModem main、Generic main 与 OpenClash 源（插件选择在 feeds 安装后进行）'
echo '已排除旧 ModemBand、旧短信、PassWall、SmartDNS、ZeroTier'
echo '首次使用：在官方 QModem 页面扫描并拨号；多 WAN 策略按需手动配置。'
