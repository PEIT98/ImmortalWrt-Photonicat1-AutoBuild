#!/bin/bash
source "$(dirname "$0")/common.sh"
setup() { :; }
test_runtime_dependencies() {
    assert_has "$ROOT/photonicat1.config" '# CONFIG_PACKAGE_jq is not set'
    for name in jq-full coreutils-dd coreutils-od coreutils-timeout coreutils-stat sfdisk partx-utils blockdev blkid losetup resize2fs f2fsck mkf2fs; do assert_has "$ROOT/photonicat1.config" "CONFIG_PACKAGE_$name=y"; done
    assert_not_has "$ROOT/photonicat1.config" CONFIG_BUSYBOX_CONFIG_HEXDUMP
}
test_self_contained_resources() {
    for name in luci-app-online-upgrade luci-app-swrt-disk-keepalive; do
        app="$ROOT/packages/$name"
        assert_not_has "$app/Makefile" +wlmb-server
        for view in "$app"/root/www/luci-static/resources/view/system/*.js; do
            while IFS= read -r asset; do assert_file "$app/root/www/luci-static/resources/$asset"; done < <(sed -n "s/.*L.resource('\([^']*\)').*/\1/p" "$view")
        done
    done
}
plan() {
    local extra=${1:-0} overlap=${2:-0}
    touch "$TEST_TMP/mmcblk0p2"
    jq -n --arg root "$TEST_TMP" --argjson extra "$extra" --argjson overlap "$overlap" '{partitiontable:{label:"dos",sectorsize:512,id:"0x5452574f",partitions:([{node:($root+"/mmcblk0p1"),start:65536,size:32768,type:"83"},{node:($root+"/mmcblk0p2"),start:131072,size:2097152,type:"83"}]+if $extra==1 then [{node:($root+"/mmcblk0p3"),start:(if $overlap==1 then 1000000 else 8388608 end),size:1048576,type:"83"}] else [] end)}}' > "$TEST_TMP/table.json"
    sed '$d' "$ROOT/files/usr/libexec/swrt-autogrow" > "$TEST_TMP/plan.sh"
    cat >> "$TEST_TMP/plan.sh" <<'HARNESS'
WORK=$1; root="$WORK/mmcblk0p2"; disk=/unused-fixture-only; sectors=33554432
log() { :; }
sfdisk() { cat "$WORK/table.json"; }
plan
cat "$WORK/plan.json"
HARNESS
    capture sh "$TEST_TMP/plan.sh" "$TEST_TMP"
}
test_contiguous_space() { plan; assert_eq 0 "$RC"; assert_json "$OUT" '.new_size==33423360 and .start==131072'; }
test_extra_partition_boundary() { plan 1; assert_eq 0 "$RC"; assert_json "$OUT" '.new_size==8257536'; }
test_overlap_rejected() { plan 1 1; [[ $RC != 0 ]] || fail 'overlap accepted'; assert_has "$ERR" 'overlapping partition layout'; }
test_native_upgrade_write_targets() {
    local platform="$TEST_TMP/target/linux/rockchip/armv8/base-files/lib/upgrade/platform.sh"
    mkdir -p "$(dirname "$platform")"
    cp "$ROOT/scripts/tests/fixtures/rockchip-platform.sh" "$platform"
    cp "$ROOT/scripts/tests/fixtures/rockchip-storage.config" "$TEST_TMP/target/linux/rockchip/armv8/config-6.12"
    ok sh "$ROOT/scripts/patches/enable-emmc-autogrow.sh" "$TEST_TMP"
    cp "$platform" "$TEST_TMP/upgrade.sh"
    rewrite "$TEST_TMP/upgrade.sh" /tmp/ "$TEST_TMP/"
    printf '1 65536 32768\n2 131072 8257536\n3 8388608 1048576\n' > "$TEST_TMP/fixture.bootdisk"
    printf '1 65536 32768\n2 131072 2097152\n' > "$TEST_TMP/fixture.image"
    cat >> "$TEST_TMP/upgrade.sh" <<'HARNESS'
QA_ROOT=$1
export_bootdevice() { return 0; }
export_partdevice() { eval "$1=fixture-part$2"; }
get_partitions() { cp "$QA_ROOT/fixture.$2" "$QA_ROOT/partmap.$2"; }
get_image() { printf 'fixture bytes'; }
dd() { cat >/dev/null; printf '%s\n' "$*" >> "$QA_ROOT/calls"; }
partx() { printf 'UNEXPECTED PARTX\n' >> "$QA_ROOT/calls"; }
ask_bool() { return 1; }
sync() { :; }
UPGRADE_OPT_SAVE_PARTITIONS=1
platform_check_image fixture.img
platform_do_upgrade fixture.img
HARNESS
    ok sh "$TEST_TMP/upgrade.sh" "$TEST_TMP"
    assert_has "$TEST_TMP/calls" 'of=/dev/fixture-part1'
    assert_has "$TEST_TMP/calls" count=32768
    assert_has "$TEST_TMP/calls" 'of=/dev/fixture-part2'
    assert_has "$TEST_TMP/calls" count=2097152
    assert_has "$TEST_TMP/calls" 'of=/dev/fixture-part0'
    assert_has "$TEST_TMP/calls" count=4
    assert_not_has "$TEST_TMP/calls" fixture-part3
    assert_not_has "$TEST_TMP/calls" UNEXPECTED
}
run_tests "$@"
