#!/bin/bash
# Check configuration inheritance, source-patch safety and preparation cleanup.
source "$(dirname "$0")/common.sh"
setup() { :; }
mcu_harness() {
    local project="$TEST_TMP/project"
    mkdir -p "$project/scripts/build" "$project/scripts/lib" "$TEST_TMP/patch-tmp"
    cp "$ROOT/scripts/lib/patch.sh" "$project/scripts/lib/"
    harness="$project/scripts/build/prepare.sh"
    printf '#!/bin/bash\nset -euo pipefail\n' > "$harness"
    sed -n '/^switch_pcat_manager() ($/,/^)/p' "$ROOT/scripts/build/prepare.sh" >> "$harness"
    cat >> "$harness" <<'HARNESS'
parent_trace=$2
trap 'printf "parent-cleanup\n" >> "$parent_trace"' EXIT
switch_pcat_manager "$1"
printf 'parent-continued\n' >> "$parent_trace"
HARNESS
    platform="$TEST_TMP/armv8.mk"; trace="$TEST_TMP/cleanup.log"
    cat > "$platform" <<'PLATFORM'
# unrelated device defaults remain unchanged
define Device/ariaboard_photonicat
  DEVICE_PACKAGES := pcat-mgr kmod-ath10k-sdio
endef
define Device/ariaboard_photonicat2
  DEVICE_PACKAGES := pcat-mgr other-driver
endef
PLATFORM
}
test_mcu_switch_preserves_other_devices_and_parent_cleanup() {
    mcu_harness
    ok env TMPDIR="$TEST_TMP/patch-tmp" bash "$harness" "$platform" "$trace"
    assert_has "$platform" 'DEVICE_PACKAGES := luci-app-photonicat-power kmod-ath10k-sdio'
    assert_has "$platform" 'DEVICE_PACKAGES := pcat-mgr other-driver'
    assert_eq $'parent-continued\nparent-cleanup' "$(cat "$trace")"
    assert_eq '' "$(find "$TEST_TMP/patch-tmp" -mindepth 1 -print -quit)"
    cp "$platform" "$TEST_TMP/once"
    ok env TMPDIR="$TEST_TMP/patch-tmp" bash "$harness" "$platform" "$trace"
    assert_same "$platform" "$TEST_TMP/once"
    assert_eq '' "$(find "$TEST_TMP/patch-tmp" -mindepth 1 -print -quit)"
    assert_absent "$ROOT/scripts/build/switch-pcat-manager.sh"
    assert_has "$ROOT/scripts/build/prepare.sh" 'switch_pcat_manager "$SRC/target/linux/rockchip/image/armv8.mk"'
}
test_mcu_switch_rejects_changed_layout_without_writing() {
    mcu_harness
    rewrite "$platform" ariaboard_photonicat2 ariaboard_photonicat
    cp "$platform" "$TEST_TMP/before"
    reject env TMPDIR="$TEST_TMP/patch-tmp" bash "$harness" "$platform" "$trace"
    assert_same "$platform" "$TEST_TMP/before"
    assert_eq parent-cleanup "$(cat "$trace")"
    assert_eq '' "$(find "$TEST_TMP/patch-tmp" -mindepth 1 -print -quit)"
}
istore_fixture() {
    istore="$TEST_TMP/istore"
    local feed="$istore/feeds/istore" package
    mkdir -p "$istore/package/feeds/istore"
    for package in luci-app-store luci-lib-taskd luci-lib-xterm taskd; do
        mkdir -p "$feed/luci/$package"
        printf '# dependency fixture\n' > "$feed/luci/$package/Makefile"
        ln -s "$feed/luci/$package" "$istore/package/feeds/istore/$package"
    done
    app="$feed/luci/luci-app-store/Makefile"
    cat > "$app" <<'MAKEFILE'
# Apache-2.0; keep unrelated package settings
include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI based ipk/apk store
LUCI_DEPENDS:=+curl +tar +luci-lib-taskd
PKG_VERSION:=0.2.1-r1

include $(TOPDIR)/feeds/luci/luci.mk
# call BuildPackage - OpenWrt buildroot signature
MAKEFILE
    patch="$ROOT/scripts/patches/fix-istore-25.12.sh"
}
test_istore_patch_preserves_feed_links_and_is_idempotent() {
    istore_fixture
    ok sh "$patch" "$istore"
    assert_has "$app" 'LUCI_NAME:=luci-app-store'
    assert_has "$app" 'PKG_NAME:=luci-app-store'
    assert_has "$app" 'LUCI_DEPENDS:=+curl +tar +luci-lib-taskd'
    assert_has "$app" '# Apache-2.0; keep unrelated package settings'
    [[ -L "$istore/package/feeds/istore/luci-app-store" ]] || fail 'feed symlink replaced'
    cp "$app" "$TEST_TMP/once"
    ok sh "$patch" "$istore"
    assert_same "$app" "$TEST_TMP/once"
}
test_istore_existing_names_are_normalized() {
    istore_fixture
    printf '\nLUCI_NAME ?= luci-app-store\nPKG_NAME = luci-app-store # existing identity\n' >> "$app"
    ok sh "$patch" "$istore"
    assert_eq 1 "$(grep -c '^LUCI_NAME:=' "$app")"
    assert_eq 1 "$(grep -c '^PKG_NAME:=' "$app")"
    cp "$app" "$TEST_TMP/once"
    ok sh "$patch" "$istore"
    assert_same "$app" "$TEST_TMP/once"
}
test_istore_failure_keeps_original_source() {
    istore_fixture
    cp "$app" "$TEST_TMP/base"
    local variant
    for variant in missing_marker missing_include duplicate_include conflicting_name duplicate_name; do
        cp "$TEST_TMP/base" "$app"
        case "$variant" in
            missing_marker) rewrite "$app" '# call BuildPackage' '# changed package marker' ;;
            missing_include) rewrite "$app" 'include $(TOPDIR)/rules.mk' 'include $(TOPDIR)/changed.mk' ;;
            duplicate_include) printf '\ninclude $(TOPDIR)/rules.mk\n' >> "$app" ;;
            conflicting_name) printf '\nPKG_NAME:=unexpected-package\n' >> "$app" ;;
            duplicate_name) printf '\nLUCI_NAME:=luci-app-store\nLUCI_NAME:=luci-app-store\n' >> "$app" ;;
        esac
        cp "$app" "$TEST_TMP/before"
        reject sh "$patch" "$istore"
        assert_same "$app" "$TEST_TMP/before"
    done
    cp "$TEST_TMP/base" "$app"; cp "$app" "$TEST_TMP/before"
    mv "$istore/feeds/istore/luci/taskd/Makefile" "$istore/feeds/istore/luci/taskd/Makefile.disabled"
    reject sh "$patch" "$istore"
    assert_same "$app" "$TEST_TMP/before"
}
test_config_inheritance_and_passwall() {
    printf '# untouched\nCONFIG_PACKAGE_unrelated=y\nCONFIG_PACKAGE_luci-app-qmodem-next=m\nCONFIG_PACKAGE_luci-app-passwall_INCLUDE_Foo=y\n' > "$TEST_TMP/config"
    ok sh "$ROOT/scripts/build/select-packages.sh" "$TEST_TMP/config"
    assert_has "$TEST_TMP/config" '# untouched'
    assert_has "$TEST_TMP/config" 'CONFIG_PACKAGE_unrelated=y'
    assert_has "$TEST_TMP/config" 'CONFIG_PACKAGE_luci-app-qmodem-next=y'
    assert_not_has "$TEST_TMP/config" 'CONFIG_PACKAGE_luci-app-qmodem-next=m'
    assert_has "$TEST_TMP/config" '# CONFIG_PACKAGE_luci-app-passwall_INCLUDE_Foo is not set'
    awk 'BEGIN{bad=0} /^(# )?CONFIG_/ {key=$0;sub(/^# /,"",key);sub(/(=| is not set).*$/,"",key);if(seen[key]++)bad=1}END{exit bad}' "$TEST_TMP/config"
}
test_invalid_override_does_not_write() {
    mkdir -p "$TEST_TMP/project/scripts/build" "$TEST_TMP/project/scripts/lib"
    cp "$ROOT/scripts/build/select-packages.sh" "$TEST_TMP/project/scripts/build/"
    cp "$ROOT/scripts/lib/patch.sh" "$TEST_TMP/project/scripts/lib/"
    printf '# preserved\nCONFIG_PACKAGE_unrelated=y\n' > "$TEST_TMP/config"
    cp "$TEST_TMP/config" "$TEST_TMP/original"
    for content in $'CONFIG_FOO=y\nCONFIG_FOO=m\n' 'invalid entry' 'CONFIG_FOO=$(touch forbidden)'; do
        printf '%s\n' "$content" > "$TEST_TMP/project/photonicat1.config"
        reject sh "$TEST_TMP/project/scripts/build/select-packages.sh" "$TEST_TMP/config"
        assert_same "$TEST_TMP/config" "$TEST_TMP/original"
    done
}
test_package_patch_is_self_contained() {
    assert_same "$ROOT/scripts/lib/patch.sh" "$ROOT/packages/luci-app-photonicat-power/files/patch-common.sh"
    assert_has "$ROOT/packages/luci-app-photonicat-power/Makefile" 'sh ./files/patch-main.sh'
    assert_has "$ROOT/packages/luci-app-photonicat-power/Makefile" 'sh ./files/patch-photonicat-ups.sh'
}
test_empty_and_duplicate_anchors_rejected() {
    mkdir -p "$TEST_TMP/project/scripts/lib"
    cp "$ROOT/scripts/lib/patch.sh" "$TEST_TMP/project/scripts/lib/"
    cat > "$TEST_TMP/project/edit.sh" <<'EDIT'
#!/bin/sh
set -eu
. "$(dirname "$0")/scripts/lib/patch.sh"
pc_init
pc_load "$1"
pc_replace 'first' 'replaced' 'first'
pc_replace 'second' 'changed' 'second'
pc_commit
EDIT
    for text in '' 'first first second' 'first only'; do
        printf '%s' "$text" > "$TEST_TMP/source"; cp "$TEST_TMP/source" "$TEST_TMP/before"
        reject sh "$TEST_TMP/project/edit.sh" "$TEST_TMP/source"; assert_same "$TEST_TMP/source" "$TEST_TMP/before"
    done
    printf 'first second\n' > "$TEST_TMP/source"
    ok sh "$TEST_TMP/project/edit.sh" "$TEST_TMP/source"; assert_eq 'replaced changed' "$(cat "$TEST_TMP/source")"
    ok sh "$TEST_TMP/project/edit.sh" "$TEST_TMP/source"; assert_eq 'replaced changed' "$(cat "$TEST_TMP/source")"
}
run_tests "$@"
