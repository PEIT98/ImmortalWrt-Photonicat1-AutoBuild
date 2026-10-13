#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Based on gooyjq/luci-app-online-upgrade; safe Photonicat1 read-only checker.
# NEVER downloads a firmware image, restores an archive or invokes sysupgrade.
set -eu

case "$*" in
    check|"") ;;
    *) echo "错误：光影猫固件检查器目前为只读模式；不支持自动刷写或恢复。"; exit 2 ;;
esac

REPO="PEIT98/ImmortalWrt-Photonicat1-AutoBuild"
API="https://api.github.com/repos/$REPO/releases/latest"
TMP="$(mktemp /tmp/photonicat-upgrade.XXXXXX)"
META="$(mktemp /tmp/photonicat-buildinfo.XXXXXX)"
trap 'rm -f "$TMP" "$META"' EXIT
trap 'exit 1' HUP INT TERM

printf '%s\n' "===== 光影猫一代在线固件检查 =====" "设备：Ariaboard Photonicat1 / Rockchip RK3568" "来源：$REPO"
if ! curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 10 --max-time 40 --retry 2 \
    --header 'Accept: application/vnd.github+json' --header 'User-Agent: Photonicat1-Online-Upgrade' \
    --output "$TMP" "$API"; then
    echo '错误：无法连接 GitHub Releases，请检查网络或稍后重试。' >&2
    exit 1
fi

TAG="$(jsonfilter -i "$TMP" -e '@.tag_name' 2>/dev/null || true)"
case "$TAG" in
    ''|*[!A-Za-z0-9._-]*)
        echo '错误：Release 标签无效，已停止。' >&2
        exit 1 ;;
esac
PUBLISHED="$(jsonfilter -i "$TMP" -e '@.published_at' 2>/dev/null || true)"
NAMES="$(jsonfilter -i "$TMP" -e '@.assets[*].name' 2>/dev/null || true)"
EXT4="$(printf '%s\n' "$NAMES" | grep -E '^immortalwrt-rockchip-armv8-ariaboard_photonicat-ext4-sysupgrade(_[0-9]{10})?\.img\.gz$' | head -n1 || true)"
SQUASHFS="$(printf '%s\n' "$NAMES" | grep -E '^immortalwrt-rockchip-armv8-ariaboard_photonicat-squashfs-sysupgrade(_[0-9]{10})?\.img\.gz$' | head -n1 || true)"
SUMS="$(printf '%s\n' "$NAMES" | grep -Fx 'SHA256SUMS.txt' || true)"
if [ -z "$EXT4" ] && [ -z "$SQUASHFS" ]; then
    echo '错误：本次 Release 没有光影猫一代 RK3568 镜像；已拒绝其它设备镜像。' >&2
    exit 1
fi

[ -n "$PUBLISHED" ] || PUBLISHED="未知"
echo "最新 Release：$TAG"
echo "发布时间 (UTC)：$PUBLISHED"
CURRENT="$(sed -n 's/^Builder commit: //p' /etc/photonicat1-build-info 2>/dev/null | head -n1 || true)"
[ -n "$CURRENT" ] || CURRENT="未知"
echo "当前固件构建提交：$CURRENT"
REMOTE=""
if printf '%s\n' "$NAMES" | grep -Fxq 'build-sources.txt'; then
    if curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 8 --max-time 25 \
        --output "$META" "https://github.com/$REPO/releases/download/$TAG/build-sources.txt" 2>/dev/null; then
        REMOTE="$(sed -n 's/^Workflow repo commit: //p' "$META" | head -n1)"
    fi
fi
[ -n "$REMOTE" ] || REMOTE="未知"
echo "最新固件构建提交：$REMOTE"
if [ "$REMOTE" != "未知" ] && [ "$CURRENT" != "未知" ]; then
    if [ "$REMOTE" = "$CURRENT" ]; then
        echo "版本判断：当前固件与最新 Release 的构建提交相同。"
    else
        echo "版本判断：发现不同的固件构建提交，请阅读更新说明后决定是否升级。"
    fi
else
    echo "版本判断：缺少完整的构建提交信息，不能自动判断新旧。"
fi

echo "镜像列表（只能选择与当前根文件系统类型相同的镜像）："
[ -z "$EXT4" ] || echo "  ext4： https://github.com/$REPO/releases/download/$TAG/$EXT4"
[ -z "$SQUASHFS" ] || echo "  squashfs： https://github.com/$REPO/releases/download/$TAG/$SQUASHFS"
if [ -n "$SUMS" ]; then
    echo "校验文件： https://github.com/$REPO/releases/download/$TAG/SHA256SUMS.txt"
else
    echo "警告：本次 Release 缺少 SHA256SUMS.txt，不能确认镜像完整性。"
fi
echo "更新说明： https://github.com/$REPO/releases/tag/$TAG"
echo '安全提示：当前插件仅查询版本，不下载/刷写固件；请在系统 → 备份/升级手动校验镜像与设备后升级。'
