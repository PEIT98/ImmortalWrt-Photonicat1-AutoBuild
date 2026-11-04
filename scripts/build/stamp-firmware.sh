#!/bin/sh
# 写入在线更新与发布任务共用的不可变固件身份。
set -eu
root=${1:?需要源码目录}
version=${2:?需要固件标签}
commit=${3:?需要构建提交 SHA}
printf '%s\n' "$version" | LC_ALL=C grep -Eq '^photonicat1-[0-9]{8}-[0-9]{6}-[0-9]+$' || { echo 'Invalid firmware tag' >&2; exit 1; }
printf '%s\n' "$commit" | LC_ALL=C grep -Eq '^[0-9a-f]{40}$' || { echo 'Invalid builder commit' >&2; exit 1; }
stamp=${version#photonicat1-}
day=${stamp%%-*}
[ "$(printf %.4s "$day")" != 0000 ] || { echo 'Invalid firmware year' >&2; exit 1; }
time=${stamp#*-}; time=${time%%-*}
# GNU date validates calendar dates, hour/minute/second ranges and leap years.
formatted=$(printf '%s-%s-%s %s:%s:%s' "$(printf %.4s "$day")" "$(printf %s "$day" | cut -c5-6)" "$(printf %s "$day" | cut -c7-8)" "$(printf %.2s "$time")" "$(printf %s "$time" | cut -c3-4)" "$(printf %s "$time" | cut -c5-6)")
[ "$(TZ=UTC0 date -d "$formatted" +%Y%m%d%H%M%S)" = "$day$time" ] || { echo 'Invalid firmware date' >&2; exit 1; }
mkdir -p "$root/files/etc"
jq -n --arg version "$version" --arg commit "$commit" '{repository:"PEIT98/ImmortalWrt-Photonicat1-AutoBuild",board:"ariaboard,photonicat",version:$version,commit:$commit}' > "$root/files/etc/photonicat-release.json"
