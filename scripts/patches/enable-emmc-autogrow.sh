#!/bin/sh
# 保留扩容后的 eMMC 分区；基于 SlAlot ae655185，AGPL-3.0-only。
set -eu
. "$(dirname "$0")/../lib/patch.sh"
root=${1:?需要 ImmortalWrt 根目录}
platform="$root/target/linux/rockchip/armv8/base-files/lib/upgrade/platform.sh"
kernel="$root/target/linux/rockchip/armv8/config-6.12"
helper=$(cd "$(dirname "$0")/../.." && pwd)/patches/rockchip/swrt-upgrade-partitions.sh
for option in BLK_DEV_LOOP F2FS_FS; do
    grep -Fxq "CONFIG_$option=y" "$kernel" || pc_fail "CONFIG_$option must be built in for preinit eMMC expansion"
done
hash() { sha256sum "$1" | cut -d ' ' -f1; }
original_hash=$(hash "$platform")
helper_hash=$(hash "$helper")
audit="$root/photonicat-metadata/autogrow-upgrade.json"
if [ -e "$audit" ]; then
    jq -e --arg helper "$helper_hash" --arg patched "$original_hash" '.helper_sha256==$helper and .patched_sha256==$patched' "$audit" >/dev/null || pc_fail 'Prepared partition upgrade logic changed; review before rebuilding'
    exit 0
fi
pc_init
pc_load "$platform"
old='diff="$(grep -F -x -v -f /tmp/partmap.bootdisk /tmp/partmap.image)"'
new='diff="$(swrt_partition_difference /tmp/partmap.bootdisk /tmp/partmap.image)"'
pc_require "$old" 2 'Unexpected Rockchip partition comparison implementation'
pc_require swrt_partition_difference 0 'Another expanded-partition implementation is already present'
grep -Fq UPGRADE_OPT_SAVE_PARTITIONS "$PC_WORK" || pc_fail 'Missing partition-preservation option'
PC_OLD=$old pc_awk '
/^platform_check_image\(\) \{$/ { fn="check"; checks++ }
/^platform_do_upgrade\(\) \{$/ { fn="upgrade"; upgrades++ }
{ if(fn && index($0,ENVIRON["PC_OLD"])) matches[fn]++; if($0 ~ /^}/) fn=""; print }
END { if(checks!=1 || upgrades!=1 || matches["check"]!=1 || matches["upgrade"]!=1) exit 1 }'
PC_OLD=$old PC_NEW=$new pc_awk '
BEGIN { RS="\0"; ORS=""; old=ENVIRON["PC_OLD"]; new=ENVIRON["PC_NEW"] }
{ s=$0; while(p=index(s,old)) { printf "%s%s",substr(s,1,p-1),new; s=substr(s,p+length(old)) } print s }'
cat "$helper" > "$PC_TMP/combined"
printf '\n' >> "$PC_TMP/combined"
cat "$PC_WORK" >> "$PC_TMP/combined"
cat "$PC_TMP/combined" > "$PC_WORK"
patched_hash=$(hash "$PC_WORK")
jq -n --arg original "$original_hash" --arg helper "$helper_hash" --arg patched "$patched_hash" '{source_commit:"SlAlot/ImmortalWrt_Photonicat1@ae655185",original_sha256:$original,helper_sha256:$helper,patched_sha256:$patched,preserve_expanded_root:true,builtin_storage:["BLK_DEV_LOOP","F2FS_FS"]}' > "$PC_TMP/audit"
mkdir -p "$(dirname "$audit")"
pc_commit
cp "$PC_TMP/audit" "$audit"
echo 'eMMC: expanded root partitions preserved in validation and upgrade paths'
