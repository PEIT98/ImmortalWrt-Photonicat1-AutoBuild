#!/bin/bash
source "$(dirname "$0")/common.sh"
setup() {
    rel=target/linux/rockchip/armv8/base-files/lib/upgrade/platform.sh
    platform="$TEST_TMP/$rel"
    kernel="$TEST_TMP/target/linux/rockchip/armv8/config-6.12"
    mkdir -p "$(dirname "$platform")"
    cp "$ROOT/scripts/tests/fixtures/rockchip-platform.sh" "$platform"
    cp "$ROOT/scripts/tests/fixtures/rockchip-storage.config" "$kernel"
    patch="$ROOT/scripts/patches/enable-emmc-autogrow.sh"
    printf '1 65536 32768\n2 131072 2097152\n' > "$TEST_TMP/image"
}
compare() {
    printf '%s' "$1" > "$TEST_TMP/boot"
    sh -c '. "$1"; swrt_partition_difference "$2" "$3"' sh "$ROOT/patches/rockchip/swrt-upgrade-partitions.sh" "$TEST_TMP/boot" "$TEST_TMP/image"
}
test_both_paths_and_idempotence() {
    ok sh "$patch" "$TEST_TMP"
    assert_eq 2 "$(grep -Fc 'diff="$(swrt_partition_difference ' "$platform")"
    assert_has "$platform" UPGRADE_OPT_SAVE_PARTITIONS
    cp "$platform" "$TEST_TMP/once"
    ok sh "$patch" "$TEST_TMP"
    assert_same "$platform" "$TEST_TMP/once"
}
test_unknown_and_drift() {
    sed -i s/platform_check_image/unknown_check_image/ "$platform"
    reject sh "$patch" "$TEST_TMP"
    cp "$ROOT/scripts/tests/fixtures/rockchip-platform.sh" "$platform"
    ok sh "$patch" "$TEST_TMP"
    printf '# drift\n' >> "$platform"
    reject sh "$patch" "$TEST_TMP"
}
test_first_boot_tools() {
    for name in sfdisk partx-utils blockdev losetup resize2fs f2fsck; do assert_has "$ROOT/photonicat1.config" "CONFIG_PACKAGE_$name=y"; done
    assert_has "$ROOT/files/lib/preinit/79-swrt-autogrow" 'preinit_main swrt_autogrow_preinit'
    assert_absent "$ROOT/files/usr/libexec/swrt-storage"
}
test_unrelated_comments() {
    printf '# harmless upstream documentation\n' >> "$platform"
    ok sh "$patch" "$TEST_TMP"
    assert_has "$platform" swrt_partition_difference
}
test_builtin_storage() {
    sed -i s/CONFIG_BLK_DEV_LOOP=y/CONFIG_BLK_DEV_LOOP=m/ "$kernel"
    reject sh "$patch" "$TEST_TMP"
    assert_has "$ERR" 'must be built in'
}
test_grown_and_extra_partitions() {
    for gib in 8 16 64; do assert_eq '' "$(compare "$(printf '1 65536 32768\n2 131072 %s\n' "$((gib*1024*1024*1024/512-131072))")"$'\n')"; done
    assert_eq '' "$(compare $'1 65536 32768\n2 131072 8257536\n3 8388608 1048576\n')"
}
test_layout_and_malformed_rejection() {
    for old in $'1 65536 131072\n2 262144 8388608\n' $'1 65536 32768\n2 131072 1048576\n' '' $'1 65536 32768\n2 131072 -1\n' $'1 65536 32768\n2 131072 2097152\n2 131072 9999999\n' $'1 65536 32768\n2 131072 8257536\n3 5000000 1048576\n'; do
        [[ -n $(compare "$old") ]] || fail 'invalid partition table accepted'
    done
    : > "$TEST_TMP/image"
    [[ -n $(compare $'1 65536 32768\n2 131072 2097152\n') ]] || fail 'empty image accepted'
}
run_tests "$@"
