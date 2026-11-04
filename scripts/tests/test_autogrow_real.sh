#!/bin/bash
# Only disposable sparse files and loop devices created by this test are writable.
source "$(dirname "$0")/common.sh"
available=1
[[ $(id -u) == 0 && -e /dev/loop-control ]] || available=0
for tool in losetup sfdisk partx blockdev mkfs.f2fs resize.f2fs mkfs.ext4 resize2fs mksquashfs jq od mount umount blkid; do command -v "$tool" >/dev/null || available=0; done
if [[ $available == 0 ]]; then
    if [[ ${SWRT_REQUIRE_AUTOGROW_TESTS:-0} == 1 ]]; then fail 'Required auto-expansion integration tests cannot run'; fi
    echo 'SKIP: root and Linux loop/filesystem tools required'; exit 0
fi
cleanup_disks() {
    local i
    for ((i=${#mounts_list[@]}-1;i>=0;i--)); do umount "${mounts_list[i]}" >/dev/null 2>&1 || true; done
    if [[ $hold_fd == 1 ]]; then exec 7<&-; fi
    for ((i=${#loops[@]}-1;i>=0;i--)); do losetup -d "${loops[i]}" >/dev/null 2>&1 || true; done
    rm -rf "$TEST_TMP"
}
setup() {
    loops=(); mounts_list=(); hold_fd=0; data_offset=0
    mkdir "$TEST_TMP/root-mount"; root_mount="$TEST_TMP/root-mount"
    trap cleanup_disks EXIT
}
attach() {
    local result
    result=$(losetup --find --show "$@")
    loops+=("$result"); attached=$result
}
mount_fs() {
    mount -t "$3" -o "${4:-rw}" "$1" "$2"
    mounts_list+=("$2")
}
unmount_fs() {
    umount "$1"
    local i
    for i in "${!mounts_list[@]}"; do if [[ ${mounts_list[i]} == "$1" ]]; then unset 'mounts_list[i]'; fi; done
    mounts_list=("${mounts_list[@]}")
}
detach() {
    losetup -d "$1"
    local i
    for i in "${!loops[@]}"; do if [[ ${loops[i]} == "$1" ]]; then unset 'loops[i]'; fi; done
    loops=("${loops[@]}")
}
private_node() {
    local device=$1 node=$2 number major minor
    for ((n=0;n<100;n++)); do [[ ! -f /sys/class/block/$device/dev ]] || break; sleep 0.02; done
    number=$(cat "/sys/class/block/$device/dev"); IFS=: read -r major minor <<< "$number"
    mknod -m 600 "$node" b "$major" "$minor"
}
create() {
    local gib=$1; kind=$2; extra=${3:-0}; disk_bytes=${4:-$((gib*1024*1024*1024))}
    truncate -s "$disk_bytes" "$TEST_TMP/disk.img"
    attach --partscan "$TEST_TMP/disk.img"; disk_loop=$attached
    mkdir "$TEST_TMP/dev"; disk="$TEST_TMP/dev/mmcblk0"
    private_node "${disk_loop##*/}" "$disk"
    exec 7<"$disk"; hold_fd=1
    {
        printf 'label: dos\nlabel-id: 0x5452574f\nunit: sectors\n\nstart=65536,size=32768,type=83,bootable\nstart=131072,size=2097152,type=83\n'
        if [[ $extra == 1 ]]; then printf 'start=8388608,size=1048576,type=83\n'; fi
    } | sfdisk --wipe never "$disk" > "$TEST_TMP/create.log" 2>&1
    partx -u "$disk"; part="${disk}p2"
    private_node "${disk_loop##*/}p2" "$part"
    if [[ $extra == 1 ]]; then private_node "${disk_loop##*/}p3" "${disk}p3"; fi
    sfdisk --json "$disk" | jq '.partitiontable' > "$TEST_TMP/before.json"
    # Nonzero boot-code and Rockchip loader sentinels.
    LC_ALL=C awk 'BEGIN {for(i=0;i<256;i++)printf "%c",i;for(i=0;i<184;i++)printf "%c",i}' > "$TEST_TMP/bootcode"
    dd if="$TEST_TMP/bootcode" of="$disk" conv=notrunc status=none
    for ((i=0;i<100;i++)); do printf RK-LOADER-MUST-SURVIVE; done > "$TEST_TMP/loader"
    for offset in 32768 8388608; do dd if="$TEST_TMP/loader" of="$disk" bs=1 seek="$offset" conv=notrunc status=none; done
    dd if="$disk" of="$TEST_TMP/boot.before" bs=446 count=1 status=none
    printf 'configuration and application state must survive expansion\n' > "$TEST_TMP/sentinel"
    if [[ $kind == squashfs || $kind == fresh ]]; then
        mkdir "$TEST_TMP/lower"; printf 'SWRT Photonicat 1' > "$TEST_TMP/lower/firmware"
        mksquashfs "$TEST_TMP/lower" "$TEST_TMP/root.squashfs" -noappend -no-progress -quiet -processors 1
        local bytes; bytes=$(od -An -j40 -N8 -tu8 "$TEST_TMP/root.squashfs" | tr -d ' ')
        data_offset=$(((bytes+65535)/65536*65536))
        dd if="$TEST_TMP/root.squashfs" of="$part" conv=notrunc status=none
        if [[ $kind == squashfs ]]; then
            attach --offset "$data_offset" "$part"; data=$attached
            mkfs.f2fs -f "$data" > "$TEST_TMP/mkfs.log" 2>&1
            mount_fs "$data" "$root_mount" f2fs
            cp "$TEST_TMP/sentinel" "$root_mount/saved-config"
            uuid=$(blkid -p -o value -s UUID "$data")
            unmount_fs "$root_mount"; detach "$data"
        fi
        mount_fs "$part" "$root_mount" squashfs ro
    else
        mkfs.ext4 -q -m 0 "$part"; mount_fs "$part" "$root_mount" ext4
        cp "$TEST_TMP/sentinel" "$root_mount/saved-config"; uuid=$(blkid -p -o value -s UUID "$part")
    fi
    extra_sentinel=OTHER-PARTITION-DATA-DO-NOT-TOUCH
    if [[ $extra == 1 ]]; then printf '%s' "$extra_sentinel" | dd of="${disk}p3" conv=notrunc status=none; fi
    expected=$(((extra==1 ? 8388608 : disk_bytes/1048576*2048)-131072))
    local sys="$TEST_TMP/sys" parent="$TEST_TMP/sys/devices/mmcblk0" number
    mkdir -p "$parent/mmcblk0p2" "$parent/device" "$parent/queue" "$sys/firmware/devicetree/base" "$sys/dev/block"
    printf 2 > "$parent/mmcblk0p2/partition"; printf MMC > "$parent/device/type"
    printf 0 > "$parent/removable"; printf 512 > "$parent/queue/logical_block_size"
    printf 'ariaboard,photonicat\000rockchip,rk3568\000' > "$sys/firmware/devicetree/base/compatible"
    number=$(cat "/sys/class/block/${disk_loop##*/}p2/dev")
    ln -s "$parent/mmcblk0p2" "$sys/dev/block/$number"
    local fs=squashfs; [[ $kind != ext4 ]] || fs=ext4
    printf '17 1 %s / / rw - %s /dev/root rw\n' "$number" "$fs" > "$TEST_TMP/mountinfo"
    printf 'proc /proc proc rw 0 0\n' > "$TEST_TMP/mounts"
    export SWRT_AUTOGROW_SYS="$sys" SWRT_AUTOGROW_DEV="$TEST_TMP/dev" SWRT_AUTOGROW_MOUNTINFO="$TEST_TMP/mountinfo" SWRT_AUTOGROW_MOUNTS="$TEST_TMP/mounts" SWRT_AUTOGROW_WORK="$TEST_TMP/work"
}
helper() {
    capture sh "$ROOT/files/usr/libexec/swrt-autogrow" grow
    if [[ $RC != "${1:-0}" ]]; then cat "$OUT" "$ERR" "$TEST_TMP/work/"*.log >&2 || true; fail "grow exit $RC"; fi
}
verify() {
    helper
    sfdisk --json "$disk" | jq '.partitiontable' > "$TEST_TMP/after.json"
    jq --argjson size "$expected" '.partitions[1].size=$size' "$TEST_TMP/before.json" > "$TEST_TMP/expected.json"
    assert_eq "$(jq -cS . "$TEST_TMP/expected.json")" "$(jq -cS . "$TEST_TMP/after.json")"
    dd if="$disk" of="$TEST_TMP/boot.after" bs=446 count=1 status=none; assert_same "$TEST_TMP/boot.before" "$TEST_TMP/boot.after"
    for offset in 32768 8388608; do
        dd if="$disk" of="$TEST_TMP/loader.after" bs=1 skip="$offset" count="$(stat -c %s "$TEST_TMP/loader")" status=none
        assert_same "$TEST_TMP/loader" "$TEST_TMP/loader.after"
    done
    local source="$part"
    if [[ $kind == squashfs || $kind == fresh ]]; then
        unmount_fs "$root_mount"; attach --offset "$data_offset" "$part"; source=$attached
        if [[ $kind == fresh ]]; then mkfs.f2fs -f "$source" > "$TEST_TMP/mkfs.log" 2>&1; fi
        mount_fs "$source" "$root_mount" f2fs
    fi
    if [[ $kind != fresh ]]; then assert_same "$TEST_TMP/sentinel" "$root_mount/saved-config"; assert_eq "$uuid" "$(blkid -p -o value -s UUID "$source")"; fi
    local blocks frsize; read -r blocks frsize < <(stat -f -c '%b %S' "$root_mount")
    ((blocks*frsize*100 > (expected*512-data_offset)*85)) || fail 'filesystem did not grow'
    if [[ $extra == 1 ]]; then
        dd if="${disk}p3" of="$TEST_TMP/extra.after" bs=1 count="${#extra_sentinel}" status=none
        assert_eq "$extra_sentinel" "$(cat "$TEST_TMP/extra.after")"
    fi
    unmount_fs "$root_mount"
    if [[ $kind == squashfs || $kind == fresh ]]; then detach "$source"; mount_fs "$part" "$root_mount" squashfs ro; fi
    helper
    assert_eq "$(jq -cS . "$TEST_TMP/after.json")" "$(sfdisk --json "$disk" | jq -cS .partitiontable)"
}
test_f2fs_8g() { create 8 squashfs; verify; }
test_f2fs_16g() { create 16 squashfs; verify; }
test_f2fs_64g() { create 64 squashfs; verify; }
test_ext4_8g() { create 8 ext4; verify; }
test_ext4_16g() { create 16 ext4; verify; }
test_ext4_64g() { create 64 ext4; verify; }
test_fresh_8g() { create 8 fresh; verify; }
test_fresh_16g() { create 16 fresh; verify; }
test_fresh_64g() { create 64 fresh; verify; }
test_extra_partition() { create 8 squashfs 1; verify; }
test_actual_64gb_capacity() { create 64 squashfs 0 62545461248; verify; }
test_non_mib_capacity() { create 8 fresh 0 $((8*1024*1024*1024-512)); verify; }
test_reboot_boundary() {
    create 8 squashfs
    mkdir "$TEST_TMP/bin"; printf '#!/bin/sh\nexit 1\n' > "$TEST_TMP/bin/partx"; chmod +x "$TEST_TMP/bin/partx"
    PATH="$TEST_TMP/bin:$PATH" helper 75
    assert_eq 2097152 "$(blockdev --getsz "$part")"; assert_absent "$TEST_TMP/work/filesystem.log"
    partx -u -n 2 "$disk"; verify
}
test_mounted_overlay_rejected() {
    create 8 squashfs; printf '/dev/loop42 /overlay f2fs rw 0 0\n' > "$SWRT_AUTOGROW_MOUNTS"
    helper 1; assert_eq "$(jq -cS . "$TEST_TMP/before.json")" "$(sfdisk --json "$disk" | jq -cS .partitiontable)"
}
test_optional_mountinfo_fields() {
    create 8 squashfs; sed -i 's|/ / rw -|/ /rom rw shared:1 master:2 -|' "$SWRT_AUTOGROW_MOUNTINFO"; verify
}
run_tests "$@"
