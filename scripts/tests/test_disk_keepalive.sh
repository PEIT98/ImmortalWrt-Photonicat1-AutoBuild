#!/bin/bash
source "$(dirname "$0")/common.sh"
setup() { app="$ROOT/packages/luci-app-swrt-disk-keepalive"; }
test_inventory_and_replug() { ok env SWRT_DISK_QA_IDENTITY_ONLY=1 sh "$ROOT/scripts/tests/disk_keepalive_harness.sh" "$app/root/usr/share/swrt-disk-keepalive/common.sh"; }
test_permissions_and_defaults() {
    assert_json "$app/root/usr/share/rpcd/acl.d/luci-app-swrt-disk-keepalive.json" '.["luci-app-swrt-disk-keepalive"] | .read.ubus["luci.swrt_disk_keepalive"]==["status"] and .write.ubus["luci.swrt_disk_keepalive"]==["configure","test"]'
    assert_has "$app/root/etc/config/swrt_disk_keepalive" "option enabled '0'"
    assert_not_has "$app/root/etc/config/swrt_disk_keepalive" 'list device'
}
test_direct_io() {
    if [[ $(id -u) != 0 || ! -e /dev/loop-control ]]; then echo 'SKIP: disposable loop devices unavailable'; return; fi
    for cmd in jq losetup timeout dd; do command -v "$cmd" >/dev/null || { echo "SKIP: missing $cmd"; return; }; done
    ok env SWRT_DISK_QA_IDENTITY_ONLY=0 timeout 60 sh "$ROOT/scripts/tests/disk_keepalive_harness.sh" "$app/root/usr/share/swrt-disk-keepalive/common.sh"
}
run_tests "$@"
