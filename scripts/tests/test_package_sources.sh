#!/bin/bash
source "$(dirname "$0")/common.sh"
setup() {
    app="$ROOT/packages/luci-app-photonicat-power"
    engine="$app/root/usr/libexec/photonicat-package-source"
    export PHOTONICAT_PACKAGE_ROOT="$TEST_TMP/root"
    local root=$PHOTONICAT_PACKAGE_ROOT
    mkdir -p "$root"/{bin,etc/config,etc/apk/repositories.d,tmp/sysinfo,usr/share/photonicat,var/lock}
    cp "$app/root/usr/share/photonicat/package-sources.awk" "$root/usr/share/photonicat/"
    config="$root/etc/config/photonicat_packages"
    printf "config settings 'main'\n\toption source 'nju'\n" > "$config"
    printf 'ariaboard,photonicat\n' > "$root/tmp/sysinfo/board_name"
    feed="$root/etc/apk/repositories.d/distfeeds.list"
    cat > "$feed" <<'FEEDS'
# Preserve comment: https://downloads.immortalwrt.org/releases
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/targets/rockchip/armv8/packages/packages.adb
@base	https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_generic/base/packages.adb  # keep spaces
https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/targets/rockchip/armv8/kmods/6.12.112-1-abcdef/packages.adb
https://repo.istoreos.com/istore/compatible/aarch64_generic/packages.adb
https://downloads.immortalwrt.org.evil.invalid/custom/packages.adb
FEEDS
    chmod 644 "$feed"
    cp "$feed" "$TEST_TMP/original"; cp "$config" "$TEST_TMP/config.before"
    cp "$ROOT/scripts/tests/fixtures/mock-uci-config.sh" "$root/bin/uci"
    printf '#!/bin/sh\ntouch "$PHOTONICAT_PACKAGE_ROOT/unexpected-package-action"\n' > "$root/bin/apk"
    chmod +x "$root/bin/"*
    export PATH="$root/bin:$PATH"
}
engine_ok() { ok sh "$engine" "${1:-status}" <<<"${2:-}"; assert_json "$OUT" '.ok==true'; }
engine_reject() { reject sh "$engine" "$1" <<<"$2"; assert_json "$OUT" '.ok==false'; }
test_readonly_status() {
    engine_ok
    assert_json "$OUT" '.source=="nju" and .actual=="official" and .repositories==3 and .custom_repositories==2 and .pending'
    assert_same "$config" "$TEST_TMP/config.before"; assert_same "$feed" "$TEST_TMP/original"
    assert_absent "$PHOTONICAT_PACKAGE_ROOT/unexpected-package-action"
}
test_factory_accelerator_paths_and_mode() {
    engine_ok apply
    assert_json "$OUT" '.changed==3 and .actual=="nju"'
    sed '2,4s|https://downloads.immortalwrt.org|https://mirror.nju.edu.cn/immortalwrt|' "$TEST_TMP/original" > "$TEST_TMP/expected"
    assert_same "$feed" "$TEST_TMP/expected"
    assert_eq 644 "$(stat -c %a "$feed")"
    assert_absent "$PHOTONICAT_PACKAGE_ROOT/unexpected-package-action"
}
test_saved_official_and_reboot() {
    engine_ok apply
    engine_ok set '{"source":"official"}'
    assert_json "$OUT" '.source=="official"'; assert_same "$feed" "$TEST_TMP/original"
    engine_ok apply; assert_json "$OUT" '.changed==0'
    assert_has "$config" "option source 'official'"
}
test_idempotent_mtime() {
    engine_ok apply
    local before; before=$(stat -c %y "$feed")
    engine_ok apply; assert_json "$OUT" '.changed==0'
    assert_eq "$before" "$(stat -c %y "$feed")"
}
test_new_distribution_list() {
    engine_ok apply; cp "$TEST_TMP/original" "$feed"
    engine_ok; assert_json "$OUT" '.pending'
    engine_ok apply; engine_ok; assert_json "$OUT" '.actual=="nju"'
}
test_alternate_formats_and_opkg() {
    local root=$PHOTONICAT_PACKAGE_ROOT
    printf '@test https://downloads.immortalwrt.org/snapshots/packages/aarch64_generic/base\n' > "$root/etc/apk/repositories"
    printf 'https://mirrors.nju.edu.cn/immortalwrt/releases/25.12-SNAPSHOT/packages/aarch64_generic/luci/packages.adb\n' > "$root/etc/apk/repositories.d/extra.repositories"
    mkdir "$root/etc/opkg"
    printf 'src/gz immortalwrt_base https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_generic/base\n' > "$root/etc/opkg/distfeeds.conf"
    engine_ok set '{"source":"official"}'
    assert_has "$root/etc/apk/repositories.d/extra.repositories" 'https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/packages/aarch64_generic/luci/'
    engine_ok set '{"source":"nju"}'
    assert_eq '@test https://mirror.nju.edu.cn/immortalwrt/snapshots/packages/aarch64_generic/base' "$(cat "$root/etc/apk/repositories")"
    assert_eq 'src/gz immortalwrt_base https://mirror.nju.edu.cn/immortalwrt/releases/25.12-SNAPSHOT/packages/aarch64_generic/base' "$(cat "$root/etc/opkg/distfeeds.conf")"
}
test_malformed_input() {
    for raw in '{}' '[]' '{"source":null}' '{"source":true}' '{"source":"https://example.com"}' '{"source":"official; reboot"}' '{"source":"nju"}{"source":"official"}' "$(printf '%05000d' 0)"; do
        engine_reject set "$raw"
        assert_same "$config" "$TEST_TMP/config.before"; assert_same "$feed" "$TEST_TMP/original"
    done
}
test_custom_only() {
    printf 'https://my-custom.invalid/immortalwrt/packages.adb\n' > "$feed"
    cp "$feed" "$TEST_TMP/custom"
    engine_reject set '{"source":"official"}'
    assert_same "$feed" "$TEST_TMP/custom"; assert_same "$config" "$TEST_TMP/config.before"
}
test_commit_rollback() {
    local other="$PHOTONICAT_PACKAGE_ROOT/etc/apk/repositories.d/second.list"
    printf 'https://downloads.immortalwrt.org/snapshots/packages/aarch64_generic/luci\n' > "$other"
    cp "$other" "$TEST_TMP/second"
    touch "$PHOTONICAT_PACKAGE_ROOT/uci-fail"
    engine_reject set '{"source":"nju"}'
    assert_same "$other" "$TEST_TMP/second"; assert_same "$feed" "$TEST_TMP/original"; assert_same "$config" "$TEST_TMP/config.before"
}
test_concurrent_write() {
    exec 8>"$PHOTONICAT_PACKAGE_ROOT/var/lock/photonicat-package-source.lock"
    flock -n 8
    engine_reject set '{"source":"official"}'
    assert_same "$feed" "$TEST_TMP/original"
}
test_symlink_target() {
    mv "$feed" "$PHOTONICAT_PACKAGE_ROOT/protected"
    ln -s "$PHOTONICAT_PACKAGE_ROOT/protected" "$feed"
    engine_reject set '{"source":"official"}'
    [[ -L $feed ]] || fail 'symlink replaced'
    assert_same "$PHOTONICAT_PACKAGE_ROOT/protected" "$TEST_TMP/original"
}
test_unrelated_uci_changes() {
    mkdir "$PHOTONICAT_PACKAGE_ROOT/global-uci"
    printf 'pending user network changes\n' > "$PHOTONICAT_PACKAGE_ROOT/global-uci/network"
    engine_ok set '{"source":"nju"}'
    assert_eq 'pending user network changes' "$(cat "$PHOTONICAT_PACKAGE_ROOT/global-uci/network")"
}
test_missing_config() {
    rm "$config"
    engine_ok set '{"source":"nju"}'; assert_json "$OUT" '.source=="nju"'
    assert_has "$config" "option source 'nju'"
}
test_permissions_and_package() {
    ok sh "$app/root/usr/libexec/rpcd/luci.photonicat_packages" list
    assert_json "$OUT" '.setSettings=={source:""}'
    assert_json "$app/root/usr/share/rpcd/acl.d/luci-app-photonicat-power.json" '.["luci-app-photonicat-power"]|.read.ubus["luci.photonicat_packages"]==["getSettings"] and .write.ubus["luci.photonicat_packages"]==["setSettings"]'
    for name in photonicat-package-source package-sources.awk photonicat_packages 99-photonicat-package-source; do assert_has "$app/Makefile" "$name"; done
    assert_has "$app/Makefile" '+jq-full +flock'
    assert_has "$app/root/etc/config/photonicat_packages" "option source 'nju'"
}
run_tests "$@"
