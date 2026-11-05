#!/bin/bash
# 解析实际 Feeds，检查依赖、APK 版本、菜单及安装文件冲突。
set -euo pipefail
mode=${1:?需要 dependencies、menus 或 runtime}
root=${2:-.}
next="$root/feeds/qmodem/luci/luci-app-qmodem-next"
generic="$root/feeds/qmodem_generic/luci-app-qmodem-generic"
if [[ $mode == dependencies ]]; then
    dependencies() {
        awk '/^LUCI_DEPENDS[[:space:]]*:?=/ {n++;s=$0;sub(/^[^=]*=/,"",s);print s} END{if(n!=1)exit 1}' "$1" | grep -oE '\+[A-Za-z0-9_+.-]+' | cut -c2-
    }
    next_deps=$(dependencies "$next/Makefile")
    generic_deps=$(dependencies "$generic/Makefile")
    for dep in qmodem qmodem-smsd sms-forwarder-next luci-base; do grep -Fxq "$dep" <<< "$next_deps"; done
    for dep in qmodem luci-base; do grep -Fxq "$dep" <<< "$generic_deps"; done
    version=$(awk '/^QMODEM_VERSION[[:space:]]*:?=/ {n++;s=$0;sub(/^[^=]*=[[:space:]]*/,"",s);split(s,a,/[[:space:]]/);print a[1]}END{if(n!=1)exit 1}' "$root/feeds/qmodem/version.mk")
    [[ $version =~ ^[0-9]+(\.[0-9]+)*(_(alpha|beta|pre|rc)[0-9]*)?$ ]] || { echo '::error::QModem 版本不适用于 APK' >&2; exit 1; }
elif [[ $mode == menus ]]; then
    upstream="$next/root/usr/share/luci/menu.d/luci-app-qmodem-next.json"
    alternative="$generic/root/usr/share/luci/menu.d/luci-app-qmodem-generic.json"
    override="$root/files/usr/share/luci/menu.d/zz-photonicat-modem-title.json"
    jq -e --slurpfile g "$alternative" --slurpfile o "$override" '
      has("admin/modem") and has("admin/modem/qmodem") and ($g[0]|has("admin/modem/qmodem-generic")) and
      $o==[{"admin/modem":{"title":"移动网络"}}] and
      ([keys[] as $key|select($g[0]|has($key))|$key]==["admin/modem"]) and
      .["admin/modem"].action==$g[0]["admin/modem"].action' "$upstream" >/dev/null
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    (cd "$generic/root"; find -L . -type f -printf '%P\n' | LC_ALL=C sort) > "$tmp/generic"
    for files in "$root/feeds/qmodem/application/qmodem/files" "$next/root"; do
        (cd "$files"; find -L . -type f -printf '%P\n' | LC_ALL=C sort) > "$tmp/upstream"
        LC_ALL=C comm -12 "$tmp/generic" "$tmp/upstream" > "$tmp/shared"
        if [[ -s $tmp/shared ]]; then cat "$tmp/shared" >&2; echo '::error::上游插件安装文件重名' >&2; exit 1; fi
    done
elif [[ $mode == runtime ]]; then
    # 只允许指定的计时及 USB 启动扫描修复；其他运行源码保持官方提交。
    git -C "$root/feeds/qmodem" diff --exit-code HEAD -- \
        application/qmodem application/modem_scan application/quectel_CM_5G_M driver \
        ':!application/modem_scan/src/modem_scand.c' \
        ':!application/qmodem/files/etc/init.d/qmodem_init'
    tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
    scanner=application/modem_scan/src/modem_scand.c
    init=application/qmodem/files/etc/init.d/qmodem_init
    for path in "$scanner" "$init"; do
        mkdir -p "$tmp/expected/$(dirname "$path")"
        git -C "$root/feeds/qmodem" show "HEAD:$path" > "$tmp/expected/$path"
    done
    sh "$(dirname "$0")/../patches/packages/fix-qmodem-monotonic-clock.sh" "$tmp/expected"
    sh "$(dirname "$0")/../patches/packages/fix-qmodem-boot-scan.sh" "$tmp/expected"
    for path in "$scanner" "$init"; do
        cmp -s "$tmp/expected/$path" "$root/feeds/qmodem/$path" || {
            echo "::error::QModem 存在限定修复之外的改动：$path" >&2; exit 1;
        }
    done
    extra=$(git -C "$root/feeds/qmodem" ls-files --others --exclude-standard -- \
        application/qmodem application/modem_scan application/quectel_CM_5G_M driver)
    [[ -z $extra ]] || { echo "::error::QModem 运行源码存在额外文件：$extra" >&2; exit 1; }
else
    echo '::error::未知 Feeds 校验模式' >&2; exit 1
fi
