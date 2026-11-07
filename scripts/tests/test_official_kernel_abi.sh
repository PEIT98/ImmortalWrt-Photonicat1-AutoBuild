#!/usr/bin/env bash
# 官方配置合并与 ABI 不一致时的发布保护。
source "$(dirname "$0")/common.sh"
setup() {
    SRC="$TEST_TMP/immortalwrt"
    META="$TEST_TMP/official-abi"
    mkdir -p "$SRC" "$META" "$TEST_TMP/bin"
    SCRIPT="$ROOT/scripts/build/official-kernel-abi.sh"
    printf 'CONFIG_PACKAGE_qmodem=y\nCONFIG_KERNEL_DEBUG_INFO_BTF=n\nCONFIG_KERNEL_OLD=y\nCONFIG_ALL_KMODS=n\n' > "$SRC/.config"
    printf 'CONFIG_KERNEL_DEBUG_INFO_BTF=y\n# CONFIG_KERNEL_OLD is not set\nCONFIG_ALL_KMODS=y\nCONFIG_KERNEL_BUILD_USER="buildbot"\n' > "$META/config.buildinfo"
    printf 'kernel-6.12.112~4ce22fc78523e0739bdb12c4ffdd2e26-r1.apk\n' > "$META/kernel-package"
    cat > "$TEST_TMP/bin/curl" <<'CURL'
#!/bin/sh
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then
    shift
    printf '<a href="kmod-usb-net-cdc-mbim-6.12.112-r1.apk">module</a>\n' > "$1"
    exit 0
  fi
  shift
done
exit 1
CURL
    chmod +x "$TEST_TMP/bin/curl"
}
test_merge_preserves_plugins_and_replaces_kernel_options() {
    ok bash "$SCRIPT" merge "$SRC" "$META"
    assert_has "$SRC/.config" 'CONFIG_PACKAGE_qmodem=y'
    assert_has "$SRC/.config" 'CONFIG_KERNEL_DEBUG_INFO_BTF=y'
    assert_has "$SRC/.config" '# CONFIG_KERNEL_OLD is not set'
    assert_has "$SRC/.config" 'CONFIG_ALL_KMODS=y'
    assert_has "$SRC/.config" 'CONFIG_KERNEL_BUILD_USER="buildbot"'
    assert_not_has "$SRC/.config" 'CONFIG_KERNEL_OLD=y'
    ok bash "$SCRIPT" merge "$SRC" "$META"
    assert_eq 1 "$(grep -c '^CONFIG_KERNEL_BUILD_USER=' "$SRC/.config")"
}
test_pin_uses_official_revision_and_kernel_package() {
    cat > "$TEST_TMP/bin/curl" <<'CURL'
#!/bin/sh
url=; output=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift; output=$1 ;;
    http*) url=$1 ;;
  esac
  shift
done
case "$url" in
  */version.buildinfo) value='r38263-84b665b5de' ;;
  */config.buildinfo) value='CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_ariaboard_photonicat=y' ;;
  */packages/) value='<a href="kernel-6.12.112~4ce22fc78523e0739bdb12c4ffdd2e26-r1.apk">kernel</a>' ;;
  */commits/84b665b5de) value='{"sha":"84b665b5de552e297d0f7d755b88a46fc0cfeb13"}' ;;
  *) exit 1 ;;
esac
if [ -n "$output" ]; then printf '%s\n' "$value" > "$output"; else printf '%s\n' "$value"; fi
CURL
    cat > "$TEST_TMP/bin/git" <<'GIT'
#!/bin/sh
[ "$1" = -C ] || exit 1
shift 2
case "$1" in
  fetch) [ "$2" = --depth=1 ] && [ "$3" = origin ] &&
    [ "$4" = 84b665b5de552e297d0f7d755b88a46fc0cfeb13 ] ;;
  checkout) [ "$2" = --detach ] && [ "$3" = FETCH_HEAD ] ;;
  rev-parse) printf '%s\n' 84b665b5de552e297d0f7d755b88a46fc0cfeb13 ;;
  *) exit 1 ;;
esac
GIT
    chmod +x "$TEST_TMP/bin/curl" "$TEST_TMP/bin/git"
    ok env PATH="$TEST_TMP/bin:$PATH" bash "$SCRIPT" pin "$SRC" "$META"
    assert_eq 'kernel-6.12.112~4ce22fc78523e0739bdb12c4ffdd2e26-r1.apk' "$(cat "$META/kernel-package")"
    assert_has "$OUT" '官方源码：r38263-84b665b5de'
}
test_feed_uses_pinned_kernel_and_is_switchable() {
    ok bash "$SCRIPT" feed "$SRC" "$META"
    local feed="$SRC/files/etc/apk/repositories.d/pwrt-kmods.list"
    assert_eq 'https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/targets/rockchip/armv8/kmods/6.12.112-1-4ce22fc78523e0739bdb12c4ffdd2e26/packages.adb' "$(cat "$feed")"
    assert_eq 644 "$(stat -c %a "$feed")"
    ok bash "$SCRIPT" feed "$SRC" "$META"
    assert_eq 1 "$(wc -l < "$feed")"
    printf 'kernel-bad-version.apk\n' > "$META/kernel-package"
    reject bash "$SCRIPT" feed "$SRC" "$META"
    assert_has "$feed" '/6.12.112-1-4ce22fc78523e0739bdb12c4ffdd2e26/'
}
test_verify_rejects_wrong_abi_and_accepts_matching_abi() {
    local dir="$SRC/bin/targets/rockchip/armv8/packages" vermagic_dir="$SRC/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/linux-6.12.112"
    mkdir -p "$dir" "$vermagic_dir"
    printf '9d6c6042e3a0d92e7f5781589d3a9ac8\n' > "$vermagic_dir/.vermagic"
    touch "$dir/kernel-6.12.112~9d6c6042e3a0d92e7f5781589d3a9ac8-r1.apk"
    reject env PATH="$TEST_TMP/bin:$PATH" bash "$SCRIPT" verify "$SRC" "$META"
    assert_has "$ERR" '内核 ABI 与官方不一致'
    rm "$dir"/*.apk
    touch "$dir/$(cat "$META/kernel-package")"
    reject env PATH="$TEST_TMP/bin:$PATH" bash "$SCRIPT" verify "$SRC" "$META"
    assert_has "$ERR" '实际内核 .vermagic 与官方 ABI 不一致'
    printf '4ce22fc78523e0739bdb12c4ffdd2e26\n' > "$vermagic_dir/.vermagic"
    ok env PATH="$TEST_TMP/bin:$PATH" bash "$SCRIPT" verify "$SRC" "$META"
    assert_has "$OUT" '均为官方 ABI'
}
run_tests "$@"
