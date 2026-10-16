#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# 基于 gooyjq/luci-app-online-upgrade，参考 LianXia233/H5000M-CI-Qmodem。
# 光影猫一代适配：只匹配本机镜像、核对 SHA256 和 sysupgrade -T，手动升级。

SYSROOT="${ONLINE_UPGRADE_ROOT:-}"
TMP="$SYSROOT/tmp"
IDENTITY="$SYSROOT/etc/online-upgrade-device"
[ ! -f "$SYSROOT/rom/etc/online-upgrade-device" ] || IDENTITY="$SYSROOT/rom/etc/online-upgrade-device"
STATUS="$TMP/online-upgrade-status"
LOG="$TMP/online-upgrade.log"
MODE="${1:-check}"
mkdir -p "$TMP" || exit 1

get_uci() { uci -q get "online-upgrade.settings.$1" 2>/dev/null; }
set_status() { printf '%s\n' "$1" > "$STATUS"; }
fail() {
    printf '错误：%s\n' "$1"
    case "$MODE" in upgrade|upgrade-force) set_status "failed:$1" ;; esac
    exit 1
}

case "$MODE" in
    background|background-force)
        child=upgrade
        [ "$MODE" != background-force ] || child=upgrade-force
        exec 9>"$TMP/online-upgrade.lock"
        flock -n 9 || { echo '错误：另一个升级或备份任务正在运行'; exit 1; }
        set_status checking
        setsid /bin/sh "$0" "_$child" </dev/null >"$LOG" 2>&1 &
        exit 0
        ;;
    _upgrade|_upgrade-force) MODE="${MODE#_}"; inherited_lock=1 ;;
    check|upgrade|upgrade-force|backup) ;;
    reset|--reset) rm -f "$STATUS"; exit 0 ;;
    *) printf '用法：%s check|upgrade|upgrade-force|background|backup|reset\n' "$0"; exit 1 ;;
esac

# flock 随进程退出自动释放，不留下阻塞下一次操作的目录锁。
case "$MODE" in
    upgrade|upgrade-force|backup)
        [ "${inherited_lock:-0}" = 1 ] || exec 9>"$TMP/online-upgrade.lock"
        flock -n 9 || { echo '错误：另一个升级或备份任务正在运行'; exit 1; }
        set_status checking
        ;;
esac
WORK=$(mktemp -d "$TMP/online-upgrade.XXXXXX") || fail '无法创建临时目录'
trap 'rm -rf "$WORK"' EXIT
trap 'exit 1' HUP INT TERM

make_backup() {
    mkdir -p "$SYSROOT/root" || fail '无法创建备份目录'
    BACKUP="$WORK/pre-upgrade-backup.tar.gz"
    sysupgrade -b "$BACKUP" || fail '配置备份失败'
    [ -s "$BACKUP" ] && gzip -t "$BACKUP" || fail '配置备份文件无效'
    BACKUP_COPY="$SYSROOT/root/pre-upgrade-backup-$(date +%Y%m%d-%H%M%S)-$$.tar.gz"
    cp "$BACKUP" "$BACKUP_COPY" || fail '无法保存备份副本'
    printf '备份成功: %s\n' "$BACKUP_COPY"
}
if [ "$MODE" = backup ]; then
    make_backup
    set_status backed_up
    exit 0
fi

REPO="$(get_uci repo)"
TAG="$(get_uci tag)"
PROXY="$(get_uci proxy)"
KEEP_CONFIG="$(get_uci keep_config)"
[ -n "$REPO" ] || REPO='PEIT98/ImmortalWrt-Photonicat1-AutoBuild'
[ -n "$TAG" ] || TAG=auto
[ -n "$KEEP_CONFIG" ] || KEEP_CONFIG=1
printf '%s\n' "$REPO" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' || fail '发布仓库格式不正确'
case "$KEEP_CONFIG" in 0|1) ;; *) fail '保留配置选项无效' ;; esac
if [ -n "$PROXY" ]; then
    case "$PROXY" in https://*) ;; *) fail '下载加速地址必须使用 HTTPS' ;; esac
    case "$PROXY" in *[[:space:]]*|*@*|*\?*|*\#*) fail '下载加速地址格式不正确' ;; esac
    PROXY="${PROXY%/}/"
fi
TAG_PATTERN='^photonicat1-[0-9]{8}-[0-9]{6}-[0-9]+$'
if [ "$TAG" != auto ]; then
    printf '%s\n' "$TAG" | grep -Eq "$TAG_PATTERN" || fail 'Release 标签不属于本项目光影猫固件'
fi

BUILD_TAG=''
DEVICE_BOARD=''
[ ! -f "$IDENTITY" ] || . "$IDENTITY"
BOARD=$(cat "$SYSROOT/tmp/sysinfo/board_name" 2>/dev/null)
if [ -z "$BOARD" ]; then
    BOARD=$(ubus -S call system board 2>/dev/null | jq -r '.board_name // empty' 2>/dev/null)
fi
case "$MODE" in
    upgrade|upgrade-force)
        case "$BOARD" in ariaboard,photonicat|ariaboard_photonicat) ;; *) fail '当前设备不是光影猫一代，已停止升级' ;; esac
        [ "$DEVICE_BOARD" = 'ariaboard,photonicat' ] || fail '缺少本项目固件身份，请先手动刷入包含在线升级的新固件'
        printf '%s\n' "$BUILD_TAG" | grep -Eq "$TAG_PATTERN" || fail '当前固件版本记录无效'
        ;;
esac

# API 始终通过 GitHub HTTPS 获取；不向下载加速站发送令牌或请求版本数据。
API="https://api.github.com/repos/$REPO"
if [ "$TAG" = auto ]; then
    API="$API/releases?per_page=30"
else
    API="$API/releases/tags/$TAG"
fi
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    --connect-timeout 5 --max-time 15 -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: Photonicat1-Online-Upgrade' -o "$WORK/releases.json" "$API" || fail '无法获取 GitHub 发布信息，请稍后重试'

# 只允许 rockchip/armv8 光影猫 squashfs sysupgrade 压缩镜像，绝不回退到 x86 或其它机型。
FW_PATTERN='^immortalwrt(-[0-9][0-9A-Za-z._-]*)?-rockchip-armv8-ariaboard_photonicat-squashfs-sysupgrade_[0-9]{10}\.img\.gz$'
jq -e --arg tags "$TAG_PATTERN" --arg fw "$FW_PATTERN" '
    (if type == "array" then . else [.] end)
    | map(select(.draft == false and .prerelease == false)
        | select(.tag_name | test($tags))
        | select([.assets[]? | select(.name | test($fw))] | length == 1))
    | sort_by(.published_at, .tag_name) | last // empty
' "$WORK/releases.json" > "$WORK/release.json" || fail '没有找到适用于光影猫一代的正式固件'
jq -e --arg fw "$FW_PATTERN" '.assets[] | select(.name | test($fw))' "$WORK/release.json" > "$WORK/asset.json" || fail '固件文件信息不完整'
LATEST_TAG=$(jq -r '.tag_name' "$WORK/release.json")
FILE_NAME=$(jq -r '.name' "$WORK/asset.json")
FILE_SIZE=$(jq -r '.size' "$WORK/asset.json")
DOWNLOAD_URL=$(jq -r '.browser_download_url' "$WORK/asset.json")
EXPECTED_SHA=$(jq -r '.digest // empty' "$WORK/asset.json" | sed -n 's/^sha256://p')
EXPECTED_URL="https://github.com/$REPO/releases/download/$LATEST_TAG/$FILE_NAME"
[ "$DOWNLOAD_URL" = "$EXPECTED_URL" ] || fail '固件下载地址与发布仓库不一致'
case "$FILE_SIZE" in ''|*[!0-9]*) fail '固件大小信息无效' ;; esac
[ "$FILE_SIZE" -gt 0 ] || fail '固件文件为空'

NEW_FIRMWARE=1
REASON='发现可用固件'
if [ "$BUILD_TAG" = "$LATEST_TAG" ]; then
    NEW_FIRMWARE=0
    REASON='已是最新版本'
elif [ -n "$BUILD_TAG" ]; then
    current_time=$(printf '%s' "$BUILD_TAG" | cut -d- -f2,3 | tr -d '-')
    latest_time=$(printf '%s' "$LATEST_TAG" | cut -d- -f2,3 | tr -d '-')
    newest_time=$(printf '%s\n%s\n' "$current_time" "$latest_time" | LC_ALL=C sort | tail -1)
    if [ "$newest_time" = "$current_time" ] && [ "$current_time" != "$latest_time" ]; then
        NEW_FIRMWARE=0
        REASON='当前构建比发布版本新'
        case "$MODE" in upgrade|upgrade-force) fail '当前构建比发布版本新，已阻止回刷旧版本' ;; esac
    fi
fi
printf '发布仓库: %s\n当前构建: %s\n最新 Release: %s\n' "$REPO" "${BUILD_TAG:-尚无版本记录}" "$LATEST_TAG"
printf '最新固件: %s\n新固件版本: %s\n' "$FILE_NAME" "$LATEST_TAG"
awk -v size="$FILE_SIZE" 'BEGIN {printf "文件大小: %.1f MB\n", size/1048576}'
printf '检测依据: %s\n' "$REASON"
[ "$NEW_FIRMWARE" != 1 ] || echo '发现新固件'
[ "$MODE" != check ] || exit 0
if [ "$NEW_FIRMWARE" = 0 ] && [ "$MODE" != upgrade-force ]; then
    set_status up_to_date
    exit 0
fi

# 老版本资产没有 digest 时，只从 GitHub 原地址读取同次 Release 的 SHA256 清单。
if ! printf '%s\n' "$EXPECTED_SHA" | grep -Eq '^[0-9a-fA-F]{64}$'; then
    CHECKSUM_URL=$(jq -r '.assets[]? | select(.name == "SHA256SUMS.txt") | .browser_download_url' "$WORK/release.json")
    [ "$CHECKSUM_URL" = "https://github.com/$REPO/releases/download/$LATEST_TAG/SHA256SUMS.txt" ] || fail '发布中缺少可验证的 SHA256 校验信息'
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 5 --max-time 20 -o "$WORK/SHA256SUMS.txt" "$CHECKSUM_URL" || fail '无法获取 SHA256 校验清单'
    EXPECTED_SHA=$(awk -v file="$FILE_NAME" '{name=$2; sub(/^\*/, "", name); sub(/^\.\//, "", name); if (name==file) print $1}' "$WORK/SHA256SUMS.txt")
fi
printf '%s\n' "$EXPECTED_SHA" | grep -Eq '^[0-9a-fA-F]{64}$' || fail '固件 SHA256 格式无效'
EXPECTED_SHA=$(printf '%s' "$EXPECTED_SHA" | tr 'A-F' 'a-f')
available_kib=$(df -Pk "$TMP" | awk 'NR==2 {print $4}')
case "$available_kib" in ''|*[!0-9]*) fail '无法检查固件下载空间' ;; esac
[ "$available_kib" -ge "$(( (FILE_SIZE + 1023) / 1024 + 32768 ))" ] || fail '临时存储空间不足，请释放空间后再试'

FIRMWARE="$WORK/firmware.img.gz"
download_firmware() {
    rm -f "$FIRMWARE"
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 8 --max-time 600 --speed-time 30 --speed-limit 2048 \
        -o "$FIRMWARE" "$1" || return 1
    [ -s "$FIRMWARE" ] || return 1
    actual_size=$(wc -c < "$FIRMWARE" | tr -d ' ')
    [ "$actual_size" = "$FILE_SIZE" ] || return 1
    gzip -t "$FIRMWARE" || return 1
    actual_sha=$(sha256sum "$FIRMWARE" | awk '{print $1}')
    [ "$actual_sha" = "$EXPECTED_SHA" ] || return 1
}
set_status downloading
download_ok=0
if [ -n "$PROXY" ]; then
    echo '正在通过下载加速站获取并校验固件...'
    download_firmware "${PROXY}${DOWNLOAD_URL}" && download_ok=1
fi
if [ "$download_ok" = 0 ]; then
    echo '正在通过 GitHub 原地址获取并校验固件...'
    download_firmware "$DOWNLOAD_URL" || fail '下载失败或文件校验未通过，请检查网络后重试'
fi
set_status verifying
sysupgrade -T "$FIRMWARE" || fail '系统判定固件不兼容，已停止升级'
if [ "$KEEP_CONFIG" = 1 ]; then
    set_status backing_up
    make_backup
fi
set_status sysupgrade
sync
echo '文件与机型校验通过，正在交给系统升级；请等待设备重启。'
if [ "$KEEP_CONFIG" = 1 ]; then
    sysupgrade -f "$BACKUP" "$FIRMWARE" || fail '系统升级命令执行失败'
else
    sysupgrade -n "$FIRMWARE" || fail '系统升级命令执行失败'
fi
