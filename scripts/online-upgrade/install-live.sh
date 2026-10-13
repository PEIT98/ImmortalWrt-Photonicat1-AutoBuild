#!/bin/sh
# Install the patched Photonicat1 LuCI OTA frontend/backend on a running router.
# Does not flash firmware, modify current WAN/QModem/Docker configuration,
# change online-upgrade UCI settings, or trigger GitHub Actions.
set -eu
umask 077
BASE='https://raw.githubusercontent.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/main/scripts/online-upgrade'
TMP="/tmp/photonicat-ota-install-$$"
mkdir -p "$TMP"
trap 'rm -rf "$TMP"' EXIT
trap 'exit 1' HUP INT TERM
command -v curl >/dev/null || { echo '错误：未安装 curl'; exit 1; }
command -v jsonfilter >/dev/null || { echo '错误：未安装 jsonfilter'; exit 1; }

echo '===== 下载更新文件（不会进行固件刷写）====='
for spec in 'check.sh' 'view.js' 'disk-layout.sh'; do
    curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' \
      --connect-timeout 10 --max-time 45 --retry 1 \
      -o "$TMP/$spec" "$BASE/$spec" || {
        echo "下载 $spec 失败，未修改系统。"
        exit 1
      }
    [ -s "$TMP/$spec" ] || { echo "$spec 文件为空，拒绝安装"; exit 1; }
done
sh -n "$TMP/check.sh" || { echo 'OTA Shell 脚本语法错误，拒绝安装'; exit 1; }
sh -n "$TMP/disk-layout.sh" || exit 1
grep -Fq 'check-start)' "$TMP/check.sh"
grep -Fq 'tags-worker)' "$TMP/check.sh"
grep -Fq 'sha256sum -c -' "$TMP/check.sh"
grep -Fq 'check-start' "$TMP/view.js"

CLI=/usr/bin/online-upgrade.sh
DISK=/usr/bin/photonicat-ota-disk-layout
UI=/www/luci-static/resources/view/system/online-upgrade.js
[ -f "$CLI" ] && [ -f "$UI" ] || {
    echo '未检测到原有在线升级插件，请先安装固件中内置的软件包。'
    exit 1
}
BACKUP="/root/photonicat-ota-before-$(date +%Y%m%d%H%M%S)"
mkdir -p "$BACKUP"
cp -p "$CLI" "$BACKUP/online-upgrade.sh"
cp -p "$UI" "$BACKUP/online-upgrade.js"
[ ! -f "$DISK" ] || cp -p "$DISK" "$BACKUP/photonicat-ota-disk-layout"
cp "$TMP/check.sh" "$CLI"
cp "$TMP/disk-layout.sh" "$DISK"
cp "$TMP/view.js" "$UI"
chmod 755 "$CLI" "$DISK"
chmod 644 "$UI"
rm -f /tmp/luci-indexcache 2>/dev/null || true
echo "安装成功。原文件备份：$BACKUP"
echo '请在浏览器对路由器 LuCI 页面强制刷新（Ctrl+F5），再测试「检查最新固件」。'
echo '此操作不下载或刷写固件，也不会重启路由器。'
