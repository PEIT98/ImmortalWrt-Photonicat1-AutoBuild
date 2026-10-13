#!/bin/sh
# GPL-2.0-only; based on gooyjq/luci-app-online-upgrade.
# Photonicat1 guarded upgrade: never skip device, hash or sysupgrade -T checks.
set -eu
umask 077
WORK=/tmp/photonicat-upgrade
mkdir -p "$WORK"
STATE="$WORK/state"
LOCK="$WORK/lock"
LOG="$WORK/upgrade.log"
REPO_DEFAULT=PEIT98/ImmortalWrt-Photonicat1-AutoBuild
MODE=check
[ "$#" -eq 0 ] || MODE="$1"
ERRORS=0
tmp_release=
tmp_hash=
tmp_sources=
cleanup() {
    [ -z "$tmp_release" ] || rm -f "$tmp_release"
    [ -z "$tmp_hash" ] || rm -f "$tmp_hash"
    [ -z "$tmp_sources" ] || rm -f "$tmp_sources"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
die() { echo "错误：$1" >&2; printf 'failed|%s\n' "$1" > "$STATE"; exit 1; }
stage() { printf '%s|%s\n' "$1" "$2" > "$STATE"; echo "$2"; }
setting() { uci -q get "online-upgrade.settings.$1" 2>/dev/null || true; }
valid_repo() { printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; }
valid_tag() { [ "$1" = latest ] || printf '%s\n' "$1" | grep -Eq '^[A-Za-z0-9._-]+$'; }
valid_proxy() {
    [ -z "$1" ] && return 0
    printf '%s\n' "$1" | grep -Eq '^https://[A-Za-z0-9.-]+(:[0-9]{2,5})?(/[A-Za-z0-9_./-]*)?$'
}
device_ok() {
    [ -r /proc/device-tree/compatible ] || return 1
    tr '\000' '\n' </proc/device-tree/compatible | grep -Fxq 'ariaboard,photonicat'
}
root_type() {
    if awk '$2=="/rom" && $3=="squashfs" {found=1} END {exit !found}' /proc/mounts ||
       awk '$2=="/" && $3=="squashfs" {found=1} END {exit !found}' /proc/mounts; then
        echo squashfs
    elif awk '$2=="/" && $3=="ext4" {found=1} END {exit !found}' /proc/mounts; then
        echo ext4
    else
        echo unknown
    fi
}
download_meta() {
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 8 --max-time 25 --retry 0 \
        --header 'User-Agent: Photonicat1-OTA' -o "$1" "$2"
}
valid_custom_url() {
    printf '%s\n' "$1" | grep -Eq '^https://[A-Za-z0-9.-]+(:[0-9]{2,5})?(/[A-Za-z0-9._~%+-]+)+\.img\.gz    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 900 \
        --retry 2 --header 'User-Agent: Photonicat1-OTA' -o "$1" "$2"
}
load_release() {
    REPO="$(setting repo)"
    TAG="$(setting tag)"
    PROXY="$(setting proxy)"
    [ -n "$REPO" ] || REPO="$REPO_DEFAULT"
    [ -n "$TAG" ] || TAG=latest
    valid_repo "$REPO" || die '仓库地址不合法'
    valid_tag "$TAG" || die 'Release 标签不合法'
    valid_proxy "$PROXY" || die '代理地址必须为 HTTPS'
    FSTYPE="$(root_type)"
    [ "$FSTYPE" = ext4 ] || [ "$FSTYPE" = squashfs ] || die '无法判定当前 ext4/squashfs 根文件系统，已阻止升级'
    tmp_release="$(mktemp "$WORK/release.XXXXXX")"
    if [ "$TAG" = latest ]; then
        API="https://api.github.com/repos/$REPO/releases/latest"
    else
        API="https://api.github.com/repos/$REPO/releases/tags/$TAG"
    fi
    download "$tmp_release" "$API" || die '无法读取 GitHub Release'
    RTAG="$(jsonfilter -i "$tmp_release" -e '@.tag_name' 2>/dev/null || true)"
    printf '%s\n' "$RTAG" | grep -Eq '^[A-Za-z0-9._-]+$' || die 'Release 标签无效'
    PUBLISHED="$(jsonfilter -i "$tmp_release" -e '@.published_at' 2>/dev/null || true)"
    NAMES="$(jsonfilter -i "$tmp_release" -e '@.assets[*].name' 2>/dev/null || true)"
    NAME="$(printf '%s\n' "$NAMES" | grep -E "^immortalwrt-rockchip-armv8-ariaboard_photonicat-$FSTYPE-sysupgrade(_[0-9]{10})?\.img\.gz$" | head -n1 || true)"
    [ -n "$NAME" ] || die "Release 不包含符合当前 $FSTYPE 格式的光影猫一代固件"
    printf '%s\n' "$NAMES" | grep -Fxq SHA256SUMS.txt || die '缺少 SHA256SUMS.txt'
    SIZE="$(jsonfilter -i "$tmp_release" -e "@.assets[@.name=\"$NAME\"].size" 2>/dev/null | head -n1 || true)"
    case "$SIZE" in ''|*[!0-9]*) die '无法读取固件大小';; esac
    [ "$SIZE" -ge 1048576 ] && [ "$SIZE" -le 1073741824 ] || die '固件大小异常'
    IMG_URL="https://github.com/$REPO/releases/download/$RTAG/$NAME"
    tmp_hash="$(mktemp "$WORK/hash.XXXXXX")"
    download "$tmp_hash" "https://github.com/$REPO/releases/download/$RTAG/SHA256SUMS.txt" || die '无法读取 GitHub 原始 SHA256 清单'
    HASH="$(awk -v n="$NAME" '($2==n || $2=="./" n) && $1 ~ /^[0-9a-fA-F]+$/ {print $1}' "$tmp_hash" | head -n1)"
    [ "$(printf '%s' "$HASH" | wc -c)" -eq 64 ] || die 'SHA256 清单没有当前固件'
    CURRENT="$(sed -n 's/^Builder commit: //p' /etc/photonicat1-build-info 2>/dev/null | head -n1 || true)"
    REMOTE=""
    if printf '%s\n' "$NAMES" | grep -Fxq build-sources.txt; then
        tmp_sources="$(mktemp "$WORK/source.XXXXXX")"
        if download "$tmp_sources" "https://github.com/$REPO/releases/download/$RTAG/build-sources.txt" 2>/dev/null; then
            REMOTE="$(sed -n 's/^Workflow repo commit: //p' "$tmp_sources" | head -n1)"
        fi
    fi
}
case "$MODE" in
    settings)
        echo "repo=$(setting repo)"
        echo "tag=$(setting tag)"
        echo "proxy=$(setting proxy)"
        exit 0 ;;
    configure)
        [ "$#" -eq 4 ] || die '配置参数错误'
        valid_repo "$2" || die '仓库格式错误'
        valid_tag "$3" || die '标签格式错误'
        valid_proxy "$4" || die '代理地址必须为 HTTPS'
        uci set "online-upgrade.settings.repo=$2"
        uci set "online-upgrade.settings.tag=$3"
        uci set "online-upgrade.settings.proxy=$4"
        uci commit online-upgrade
        echo '配置已保存'
        exit 0 ;;
    status)
        if [ -e "$STATE" ]; then cat "$STATE"; else echo 'idle|未执行升级'; fi
        exit 0 ;;
    backup)
        device_ok || die '不是光影猫一代设备'
        BAK="$WORK/manual-backup.tar.gz"
        /sbin/sysupgrade -b "$BAK" || die '备份失败'
        [ -s "$BAK" ] || die '备份文件为空'
        cp "$BAK" /root/photonicat-online-upgrade-backup.tar.gz || die '保存备份失败'
        echo '备份成功：/root/photonicat-online-upgrade-backup.tar.gz'
        echo '推荐另从系统 → 备份/升级下载备份到电脑'
        exit 0 ;;
    check)
        device_ok || die '设备型号不是 Ariaboard Photonicat1'
        load_release
        echo "固件来源：$REPO"
        echo "设备：Ariaboard Photonicat1 (RK3568)"
        echo "当前根文件系统：$FSTYPE"
        echo "Release：$RTAG"
        echo "发布时间 (UTC)：$PUBLISHED"
        echo "固件名称：$NAME"
        echo "文件大小：$SIZE 字节"
        echo "固件 SHA256：$HASH"
        echo "当前构建提交：$CURRENT"
        echo "最新构建提交：$REMOTE"
        if [ -n "$CURRENT" ] && [ -n "$REMOTE" ]; then
            if [ "$CURRENT" = "$REMOTE" ]; then
                echo '版本：已是最新构建，可使用强制重装'
            else
                echo '版本：发现不同的构建版本'
            fi
        else
            echo '版本：构建信息不完整，无法判断是否更新'
        fi
        echo "固件地址：$IMG_URL"
        echo "更新说明：https://github.com/$REPO/releases/tag/$RTAG"
        # Checking must not overwrite an in-progress flashing status.
        exit 0 ;;
    start)
        [ "$#" -eq 5 ] || die '升级参数数量错误'
        case "$2" in keep|reset) ;; *) die '配置选择无效';; esac
        case "$3" in normal|force) ;; *) die '升级模式无效';; esac
        [ "$4" != latest ] || die '请提供已检查的准确 Release 标签'
        valid_tag "$4" || die '已确认的 Release 标签无效'
        printf '%s\n' "$5" | grep -Eq '^[0-9a-fA-F]{64}$' || die '已确认的 SHA256 无效'
        [ ! -d "$LOCK" ] || die '已有升级任务运行中'
        stage starting '后台升级程序正在启动'
        setsid /bin/sh "$0" run "$2" "$3" "$4" "$5" </dev/null > "$LOG" 2>&1 &
        echo '后台升级任务已启动'
        exit 0 ;;
    run)
        [ "$#" -eq 5 ] || die '升级参数数量错误'
        case "$2" in keep|reset) ;; *) die '配置选择无效';; esac
        case "$3" in normal|force) ;; *) die '升级模式无效';; esac
        mkdir "$LOCK" 2>/dev/null || die '已有升级任务运行中'
        trap 'cleanup; rmdir "$LOCK" 2>/dev/null || true' EXIT
        device_ok || die '设备身份检查失败'
        stage checking '正在获取 GitHub 发布信息及设备配置'
        load_release
        [ "$RTAG" = "$4" ] || die '最新 Release 已变化，请重新检查并确认'
        [ "$HASH" = "$5" ] || die '镜像 SHA256 已变化，请重新检查并确认'
        if [ "$3" = normal ] && [ -n "$CURRENT" ] && [ -n "$REMOTE" ] && [ "$CURRENT" = "$REMOTE" ]; then
            die '当前已是同一构建；如需重新刷写请选择强制重装'
        fi
        IMAGE="$WORK/$NAME"
        FREE="$(df -Pk "$WORK" | awk 'NR==2 {print $4}')"
        case "$FREE" in ''|*[!0-9]*) die '无法取得磁盘可用空间';; esac
        MIN_FREE="$(( (SIZE + 1023) / 1024 + 81920 ))"
        [ "$FREE" -gt "$MIN_FREE" ] || die '临时空间不足'
        stage downloading "正在下载 $NAME"
        URL="$IMG_URL"
        [ -z "$PROXY" ] || URL="$PROXY$IMG_URL"
        rm -f "$IMAGE"
        download "$IMAGE" "$URL" || die '镜像下载失败'
        DOWNLOADED="$(wc -c <"$IMAGE" | tr -d ' ')"
        [ "$DOWNLOADED" = "$SIZE" ] || die '下载大小不匹配'
        stage verifying '正在校验 SHA256 与 sysupgrade -T'
        echo "$HASH  $IMAGE" | sha256sum -c - >/dev/null 2>&1 || die 'SHA256 校验不通过'
        /sbin/sysupgrade -T "$IMAGE" >/dev/null 2>&1 || die '固件兼容性检查失败（sysupgrade -T）'
        /usr/bin/photonicat-ota-disk-layout "$IMAGE" || die '启动磁盘分区布局与镜像不同，已阻止自动升级'
        stage backup '正在生成升级前配置备份'
        BAK="$WORK/pre-upgrade.tar.gz"
        /sbin/sysupgrade -b "$BAK" || die '无法生成配置备份'
        [ -s "$BAK" ] || die '配置备份为空'
        if awk '$2=="/boot" && $3!="tmpfs" && $3!="overlay" {ok=1} END{exit !ok}' /proc/mounts; then
            BAK_KIB="$(( ($(wc -c < "$BAK" | tr -d ' ') + 1023) / 1024 ))"
            BOOT_KIB="$(df -Pk /boot | awk 'NR==2 {print $4}')"
            case "$BOOT_KIB" in ''|*[!0-9]*) BOOT_KIB=0;; esac
            if [ "$BOOT_KIB" -gt "$(( BAK_KIB + 2048 ))" ]; then
                cp "$BAK" /boot/photonicat-upgrade-backup.tar.gz && echo '配置备份已额外写入 /boot' || echo '警告：boot 分区备份失败'
            else
                echo '警告：boot 分区空间不足，跳过额外备份；不要挤占启动文件空间'
            fi
        else
            echo '提示：/boot 未挂载为持久分区，临时备份会随重启消失；请事先从 LuCI 导出到电脑'
        fi
        # Force only means reinstall an existing version. Never use sysupgrade -F.
        stage flashing '校验完成，正在执行 sysupgrade；请勿断电'
        sync
        if [ "$2" = keep ]; then
            /sbin/sysupgrade -f "$BAK" "$IMAGE" || die 'sysupgrade 执行失败'
        else
            /sbin/sysupgrade -n "$IMAGE" || die 'sysupgrade 执行失败'
        fi
        stage reboot '正在等待重启'
        exit 0 ;;
    *)
        echo 'Usage: check | configure REPO TAG PROXY | settings | status | backup | start keep/reset normal/force'
        exit 2 ;;
esac

}
valid_sha() { printf '%s\n' "$1" | grep -Eq '^[0-9a-fA-F]{64}    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 900 \
        --retry 2 --header 'User-Agent: Photonicat1-OTA' -o "$1" "$2"
}
load_release() {
    REPO="$(setting repo)"
    TAG="$(setting tag)"
    PROXY="$(setting proxy)"
    [ -n "$REPO" ] || REPO="$REPO_DEFAULT"
    [ -n "$TAG" ] || TAG=latest
    valid_repo "$REPO" || die '仓库地址不合法'
    valid_tag "$TAG" || die 'Release 标签不合法'
    valid_proxy "$PROXY" || die '代理地址必须为 HTTPS'
    FSTYPE="$(root_type)"
    [ "$FSTYPE" = ext4 ] || [ "$FSTYPE" = squashfs ] || die '无法判定当前 ext4/squashfs 根文件系统，已阻止升级'
    tmp_release="$(mktemp "$WORK/release.XXXXXX")"
    if [ "$TAG" = latest ]; then
        API="https://api.github.com/repos/$REPO/releases/latest"
    else
        API="https://api.github.com/repos/$REPO/releases/tags/$TAG"
    fi
    download "$tmp_release" "$API" || die '无法读取 GitHub Release'
    RTAG="$(jsonfilter -i "$tmp_release" -e '@.tag_name' 2>/dev/null || true)"
    printf '%s\n' "$RTAG" | grep -Eq '^[A-Za-z0-9._-]+$' || die 'Release 标签无效'
    PUBLISHED="$(jsonfilter -i "$tmp_release" -e '@.published_at' 2>/dev/null || true)"
    NAMES="$(jsonfilter -i "$tmp_release" -e '@.assets[*].name' 2>/dev/null || true)"
    NAME="$(printf '%s\n' "$NAMES" | grep -E "^immortalwrt-rockchip-armv8-ariaboard_photonicat-$FSTYPE-sysupgrade(_[0-9]{10})?\.img\.gz$" | head -n1 || true)"
    [ -n "$NAME" ] || die "Release 不包含符合当前 $FSTYPE 格式的光影猫一代固件"
    printf '%s\n' "$NAMES" | grep -Fxq SHA256SUMS.txt || die '缺少 SHA256SUMS.txt'
    SIZE="$(jsonfilter -i "$tmp_release" -e "@.assets[@.name=\"$NAME\"].size" 2>/dev/null | head -n1 || true)"
    case "$SIZE" in ''|*[!0-9]*) die '无法读取固件大小';; esac
    [ "$SIZE" -ge 1048576 ] && [ "$SIZE" -le 1073741824 ] || die '固件大小异常'
    IMG_URL="https://github.com/$REPO/releases/download/$RTAG/$NAME"
    tmp_hash="$(mktemp "$WORK/hash.XXXXXX")"
    download "$tmp_hash" "https://github.com/$REPO/releases/download/$RTAG/SHA256SUMS.txt" || die '无法读取 GitHub 原始 SHA256 清单'
    HASH="$(awk -v n="$NAME" '($2==n || $2=="./" n) && $1 ~ /^[0-9a-fA-F]+$/ {print $1}' "$tmp_hash" | head -n1)"
    [ "$(printf '%s' "$HASH" | wc -c)" -eq 64 ] || die 'SHA256 清单没有当前固件'
    CURRENT="$(sed -n 's/^Builder commit: //p' /etc/photonicat1-build-info 2>/dev/null | head -n1 || true)"
    REMOTE=""
    if printf '%s\n' "$NAMES" | grep -Fxq build-sources.txt; then
        tmp_sources="$(mktemp "$WORK/source.XXXXXX")"
        if download "$tmp_sources" "https://github.com/$REPO/releases/download/$RTAG/build-sources.txt" 2>/dev/null; then
            REMOTE="$(sed -n 's/^Workflow repo commit: //p' "$tmp_sources" | head -n1)"
        fi
    fi
}
case "$MODE" in
    settings)
        echo "repo=$(setting repo)"
        echo "tag=$(setting tag)"
        echo "proxy=$(setting proxy)"
        exit 0 ;;
    configure)
        [ "$#" -eq 4 ] || die '配置参数错误'
        valid_repo "$2" || die '仓库格式错误'
        valid_tag "$3" || die '标签格式错误'
        valid_proxy "$4" || die '代理地址必须为 HTTPS'
        uci set "online-upgrade.settings.repo=$2"
        uci set "online-upgrade.settings.tag=$3"
        uci set "online-upgrade.settings.proxy=$4"
        uci commit online-upgrade
        echo '配置已保存'
        exit 0 ;;
    status)
        if [ -e "$STATE" ]; then cat "$STATE"; else echo 'idle|未执行升级'; fi
        exit 0 ;;
    backup)
        device_ok || die '不是光影猫一代设备'
        BAK="$WORK/manual-backup.tar.gz"
        /sbin/sysupgrade -b "$BAK" || die '备份失败'
        [ -s "$BAK" ] || die '备份文件为空'
        cp "$BAK" /root/photonicat-online-upgrade-backup.tar.gz || die '保存备份失败'
        echo '备份成功：/root/photonicat-online-upgrade-backup.tar.gz'
        echo '推荐另从系统 → 备份/升级下载备份到电脑'
        exit 0 ;;
    check)
        device_ok || die '设备型号不是 Ariaboard Photonicat1'
        load_release
        echo "固件来源：$REPO"
        echo "设备：Ariaboard Photonicat1 (RK3568)"
        echo "当前根文件系统：$FSTYPE"
        echo "Release：$RTAG"
        echo "发布时间 (UTC)：$PUBLISHED"
        echo "固件名称：$NAME"
        echo "文件大小：$SIZE 字节"
        echo "固件 SHA256：$HASH"
        echo "当前构建提交：$CURRENT"
        echo "最新构建提交：$REMOTE"
        if [ -n "$CURRENT" ] && [ -n "$REMOTE" ]; then
            if [ "$CURRENT" = "$REMOTE" ]; then
                echo '版本：已是最新构建，可使用强制重装'
            else
                echo '版本：发现不同的构建版本'
            fi
        else
            echo '版本：构建信息不完整，无法判断是否更新'
        fi
        echo "固件地址：$IMG_URL"
        echo "更新说明：https://github.com/$REPO/releases/tag/$RTAG"
        # Checking must not overwrite an in-progress flashing status.
        exit 0 ;;
    start)
        [ "$#" -eq 5 ] || die '升级参数数量错误'
        case "$2" in keep|reset) ;; *) die '配置选择无效';; esac
        case "$3" in normal|force) ;; *) die '升级模式无效';; esac
        [ "$4" != latest ] || die '请提供已检查的准确 Release 标签'
        valid_tag "$4" || die '已确认的 Release 标签无效'
        printf '%s\n' "$5" | grep -Eq '^[0-9a-fA-F]{64}$' || die '已确认的 SHA256 无效'
        [ ! -d "$LOCK" ] || die '已有升级任务运行中'
        stage starting '后台升级程序正在启动'
        setsid /bin/sh "$0" run "$2" "$3" "$4" "$5" </dev/null > "$LOG" 2>&1 &
        echo '后台升级任务已启动'
        exit 0 ;;
    run)
        [ "$#" -eq 5 ] || die '升级参数数量错误'
        case "$2" in keep|reset) ;; *) die '配置选择无效';; esac
        case "$3" in normal|force) ;; *) die '升级模式无效';; esac
        mkdir "$LOCK" 2>/dev/null || die '已有升级任务运行中'
        trap 'cleanup; rmdir "$LOCK" 2>/dev/null || true' EXIT
        device_ok || die '设备身份检查失败'
        stage checking '正在获取 GitHub 发布信息及设备配置'
        load_release
        [ "$RTAG" = "$4" ] || die '最新 Release 已变化，请重新检查并确认'
        [ "$HASH" = "$5" ] || die '镜像 SHA256 已变化，请重新检查并确认'
        if [ "$3" = normal ] && [ -n "$CURRENT" ] && [ -n "$REMOTE" ] && [ "$CURRENT" = "$REMOTE" ]; then
            die '当前已是同一构建；如需重新刷写请选择强制重装'
        fi
        IMAGE="$WORK/$NAME"
        FREE="$(df -Pk "$WORK" | awk 'NR==2 {print $4}')"
        case "$FREE" in ''|*[!0-9]*) die '无法取得磁盘可用空间';; esac
        MIN_FREE="$(( (SIZE + 1023) / 1024 + 81920 ))"
        [ "$FREE" -gt "$MIN_FREE" ] || die '临时空间不足'
        stage downloading "正在下载 $NAME"
        URL="$IMG_URL"
        [ -z "$PROXY" ] || URL="$PROXY$IMG_URL"
        rm -f "$IMAGE"
        download "$IMAGE" "$URL" || die '镜像下载失败'
        DOWNLOADED="$(wc -c <"$IMAGE" | tr -d ' ')"
        [ "$DOWNLOADED" = "$SIZE" ] || die '下载大小不匹配'
        stage verifying '正在校验 SHA256 与 sysupgrade -T'
        echo "$HASH  $IMAGE" | sha256sum -c - >/dev/null 2>&1 || die 'SHA256 校验不通过'
        /sbin/sysupgrade -T "$IMAGE" >/dev/null 2>&1 || die '固件兼容性检查失败（sysupgrade -T）'
        /usr/bin/photonicat-ota-disk-layout "$IMAGE" || die '启动磁盘分区布局与镜像不同，已阻止自动升级'
        stage backup '正在生成升级前配置备份'
        BAK="$WORK/pre-upgrade.tar.gz"
        /sbin/sysupgrade -b "$BAK" || die '无法生成配置备份'
        [ -s "$BAK" ] || die '配置备份为空'
        if awk '$2=="/boot" && $3!="tmpfs" && $3!="overlay" {ok=1} END{exit !ok}' /proc/mounts; then
            BAK_KIB="$(( ($(wc -c < "$BAK" | tr -d ' ') + 1023) / 1024 ))"
            BOOT_KIB="$(df -Pk /boot | awk 'NR==2 {print $4}')"
            case "$BOOT_KIB" in ''|*[!0-9]*) BOOT_KIB=0;; esac
            if [ "$BOOT_KIB" -gt "$(( BAK_KIB + 2048 ))" ]; then
                cp "$BAK" /boot/photonicat-upgrade-backup.tar.gz && echo '配置备份已额外写入 /boot' || echo '警告：boot 分区备份失败'
            else
                echo '警告：boot 分区空间不足，跳过额外备份；不要挤占启动文件空间'
            fi
        else
            echo '提示：/boot 未挂载为持久分区，临时备份会随重启消失；请事先从 LuCI 导出到电脑'
        fi
        # Force only means reinstall an existing version. Never use sysupgrade -F.
        stage flashing '校验完成，正在执行 sysupgrade；请勿断电'
        sync
        if [ "$2" = keep ]; then
            /sbin/sysupgrade -f "$BAK" "$IMAGE" || die 'sysupgrade 执行失败'
        else
            /sbin/sysupgrade -n "$IMAGE" || die 'sysupgrade 执行失败'
        fi
        stage reboot '正在等待重启'
        exit 0 ;;
    *)
        echo 'Usage: check | configure REPO TAG PROXY | settings | status | backup | start keep/reset normal/force'
        exit 2 ;;
esac
; }
download() {
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 900 \
        --retry 2 --header 'User-Agent: Photonicat1-OTA' -o "$1" "$2"
}
load_release() {
    REPO="$(setting repo)"
    TAG="$(setting tag)"
    PROXY="$(setting proxy)"
    [ -n "$REPO" ] || REPO="$REPO_DEFAULT"
    [ -n "$TAG" ] || TAG=latest
    valid_repo "$REPO" || die '仓库地址不合法'
    valid_tag "$TAG" || die 'Release 标签不合法'
    valid_proxy "$PROXY" || die '代理地址必须为 HTTPS'
    FSTYPE="$(root_type)"
    [ "$FSTYPE" = ext4 ] || [ "$FSTYPE" = squashfs ] || die '无法判定当前 ext4/squashfs 根文件系统，已阻止升级'
    tmp_release="$(mktemp "$WORK/release.XXXXXX")"
    if [ "$TAG" = latest ]; then
        API="https://api.github.com/repos/$REPO/releases/latest"
    else
        API="https://api.github.com/repos/$REPO/releases/tags/$TAG"
    fi
    download "$tmp_release" "$API" || die '无法读取 GitHub Release'
    RTAG="$(jsonfilter -i "$tmp_release" -e '@.tag_name' 2>/dev/null || true)"
    printf '%s\n' "$RTAG" | grep -Eq '^[A-Za-z0-9._-]+$' || die 'Release 标签无效'
    PUBLISHED="$(jsonfilter -i "$tmp_release" -e '@.published_at' 2>/dev/null || true)"
    NAMES="$(jsonfilter -i "$tmp_release" -e '@.assets[*].name' 2>/dev/null || true)"
    NAME="$(printf '%s\n' "$NAMES" | grep -E "^immortalwrt-rockchip-armv8-ariaboard_photonicat-$FSTYPE-sysupgrade(_[0-9]{10})?\.img\.gz$" | head -n1 || true)"
    [ -n "$NAME" ] || die "Release 不包含符合当前 $FSTYPE 格式的光影猫一代固件"
    printf '%s\n' "$NAMES" | grep -Fxq SHA256SUMS.txt || die '缺少 SHA256SUMS.txt'
    SIZE="$(jsonfilter -i "$tmp_release" -e "@.assets[@.name=\"$NAME\"].size" 2>/dev/null | head -n1 || true)"
    case "$SIZE" in ''|*[!0-9]*) die '无法读取固件大小';; esac
    [ "$SIZE" -ge 1048576 ] && [ "$SIZE" -le 1073741824 ] || die '固件大小异常'
    IMG_URL="https://github.com/$REPO/releases/download/$RTAG/$NAME"
    tmp_hash="$(mktemp "$WORK/hash.XXXXXX")"
    download "$tmp_hash" "https://github.com/$REPO/releases/download/$RTAG/SHA256SUMS.txt" || die '无法读取 GitHub 原始 SHA256 清单'
    HASH="$(awk -v n="$NAME" '($2==n || $2=="./" n) && $1 ~ /^[0-9a-fA-F]+$/ {print $1}' "$tmp_hash" | head -n1)"
    [ "$(printf '%s' "$HASH" | wc -c)" -eq 64 ] || die 'SHA256 清单没有当前固件'
    CURRENT="$(sed -n 's/^Builder commit: //p' /etc/photonicat1-build-info 2>/dev/null | head -n1 || true)"
    REMOTE=""
    if printf '%s\n' "$NAMES" | grep -Fxq build-sources.txt; then
        tmp_sources="$(mktemp "$WORK/source.XXXXXX")"
        if download "$tmp_sources" "https://github.com/$REPO/releases/download/$RTAG/build-sources.txt" 2>/dev/null; then
            REMOTE="$(sed -n 's/^Workflow repo commit: //p' "$tmp_sources" | head -n1)"
        fi
    fi
}
case "$MODE" in
    settings)
        echo "repo=$(setting repo)"
        echo "tag=$(setting tag)"
        echo "proxy=$(setting proxy)"
        exit 0 ;;
    configure)
        [ "$#" -eq 4 ] || die '配置参数错误'
        valid_repo "$2" || die '仓库格式错误'
        valid_tag "$3" || die '标签格式错误'
        valid_proxy "$4" || die '代理地址必须为 HTTPS'
        uci set "online-upgrade.settings.repo=$2"
        uci set "online-upgrade.settings.tag=$3"
        uci set "online-upgrade.settings.proxy=$4"
        uci commit online-upgrade
        echo '配置已保存'
        exit 0 ;;
    status)
        if [ -e "$STATE" ]; then cat "$STATE"; else echo 'idle|未执行升级'; fi
        exit 0 ;;
    backup)
        device_ok || die '不是光影猫一代设备'
        BAK="$WORK/manual-backup.tar.gz"
        /sbin/sysupgrade -b "$BAK" || die '备份失败'
        [ -s "$BAK" ] || die '备份文件为空'
        cp "$BAK" /root/photonicat-online-upgrade-backup.tar.gz || die '保存备份失败'
        echo '备份成功：/root/photonicat-online-upgrade-backup.tar.gz'
        echo '推荐另从系统 → 备份/升级下载备份到电脑'
        exit 0 ;;
    check)
        device_ok || die '设备型号不是 Ariaboard Photonicat1'
        load_release
        echo "固件来源：$REPO"
        echo "设备：Ariaboard Photonicat1 (RK3568)"
        echo "当前根文件系统：$FSTYPE"
        echo "Release：$RTAG"
        echo "发布时间 (UTC)：$PUBLISHED"
        echo "固件名称：$NAME"
        echo "文件大小：$SIZE 字节"
        echo "固件 SHA256：$HASH"
        echo "当前构建提交：$CURRENT"
        echo "最新构建提交：$REMOTE"
        if [ -n "$CURRENT" ] && [ -n "$REMOTE" ]; then
            if [ "$CURRENT" = "$REMOTE" ]; then
                echo '版本：已是最新构建，可使用强制重装'
            else
                echo '版本：发现不同的构建版本'
            fi
        else
            echo '版本：构建信息不完整，无法判断是否更新'
        fi
        echo "固件地址：$IMG_URL"
        echo "更新说明：https://github.com/$REPO/releases/tag/$RTAG"
        # Checking must not overwrite an in-progress flashing status.
        exit 0 ;;
    start)
        [ "$#" -eq 5 ] || die '升级参数数量错误'
        case "$2" in keep|reset) ;; *) die '配置选择无效';; esac
        case "$3" in normal|force) ;; *) die '升级模式无效';; esac
        [ "$4" != latest ] || die '请提供已检查的准确 Release 标签'
        valid_tag "$4" || die '已确认的 Release 标签无效'
        printf '%s\n' "$5" | grep -Eq '^[0-9a-fA-F]{64}$' || die '已确认的 SHA256 无效'
        [ ! -d "$LOCK" ] || die '已有升级任务运行中'
        stage starting '后台升级程序正在启动'
        setsid /bin/sh "$0" run "$2" "$3" "$4" "$5" </dev/null > "$LOG" 2>&1 &
        echo '后台升级任务已启动'
        exit 0 ;;
    run)
        [ "$#" -eq 5 ] || die '升级参数数量错误'
        case "$2" in keep|reset) ;; *) die '配置选择无效';; esac
        case "$3" in normal|force) ;; *) die '升级模式无效';; esac
        mkdir "$LOCK" 2>/dev/null || die '已有升级任务运行中'
        trap 'cleanup; rmdir "$LOCK" 2>/dev/null || true' EXIT
        device_ok || die '设备身份检查失败'
        stage checking '正在获取 GitHub 发布信息及设备配置'
        load_release
        [ "$RTAG" = "$4" ] || die '最新 Release 已变化，请重新检查并确认'
        [ "$HASH" = "$5" ] || die '镜像 SHA256 已变化，请重新检查并确认'
        if [ "$3" = normal ] && [ -n "$CURRENT" ] && [ -n "$REMOTE" ] && [ "$CURRENT" = "$REMOTE" ]; then
            die '当前已是同一构建；如需重新刷写请选择强制重装'
        fi
        IMAGE="$WORK/$NAME"
        FREE="$(df -Pk "$WORK" | awk 'NR==2 {print $4}')"
        case "$FREE" in ''|*[!0-9]*) die '无法取得磁盘可用空间';; esac
        MIN_FREE="$(( (SIZE + 1023) / 1024 + 81920 ))"
        [ "$FREE" -gt "$MIN_FREE" ] || die '临时空间不足'
        stage downloading "正在下载 $NAME"
        URL="$IMG_URL"
        [ -z "$PROXY" ] || URL="$PROXY$IMG_URL"
        rm -f "$IMAGE"
        download "$IMAGE" "$URL" || die '镜像下载失败'
        DOWNLOADED="$(wc -c <"$IMAGE" | tr -d ' ')"
        [ "$DOWNLOADED" = "$SIZE" ] || die '下载大小不匹配'
        stage verifying '正在校验 SHA256 与 sysupgrade -T'
        echo "$HASH  $IMAGE" | sha256sum -c - >/dev/null 2>&1 || die 'SHA256 校验不通过'
        /sbin/sysupgrade -T "$IMAGE" >/dev/null 2>&1 || die '固件兼容性检查失败（sysupgrade -T）'
        /usr/bin/photonicat-ota-disk-layout "$IMAGE" || die '启动磁盘分区布局与镜像不同，已阻止自动升级'
        stage backup '正在生成升级前配置备份'
        BAK="$WORK/pre-upgrade.tar.gz"
        /sbin/sysupgrade -b "$BAK" || die '无法生成配置备份'
        [ -s "$BAK" ] || die '配置备份为空'
        if awk '$2=="/boot" && $3!="tmpfs" && $3!="overlay" {ok=1} END{exit !ok}' /proc/mounts; then
            BAK_KIB="$(( ($(wc -c < "$BAK" | tr -d ' ') + 1023) / 1024 ))"
            BOOT_KIB="$(df -Pk /boot | awk 'NR==2 {print $4}')"
            case "$BOOT_KIB" in ''|*[!0-9]*) BOOT_KIB=0;; esac
            if [ "$BOOT_KIB" -gt "$(( BAK_KIB + 2048 ))" ]; then
                cp "$BAK" /boot/photonicat-upgrade-backup.tar.gz && echo '配置备份已额外写入 /boot' || echo '警告：boot 分区备份失败'
            else
                echo '警告：boot 分区空间不足，跳过额外备份；不要挤占启动文件空间'
            fi
        else
            echo '提示：/boot 未挂载为持久分区，临时备份会随重启消失；请事先从 LuCI 导出到电脑'
        fi
        # Force only means reinstall an existing version. Never use sysupgrade -F.
        stage flashing '校验完成，正在执行 sysupgrade；请勿断电'
        sync
        if [ "$2" = keep ]; then
            /sbin/sysupgrade -f "$BAK" "$IMAGE" || die 'sysupgrade 执行失败'
        else
            /sbin/sysupgrade -n "$IMAGE" || die 'sysupgrade 执行失败'
        fi
        stage reboot '正在等待重启'
        exit 0 ;;
    *)
        echo 'Usage: check | configure REPO TAG PROXY | settings | status | backup | start keep/reset normal/force'
        exit 2 ;;
esac
