#!/usr/bin/env bash
# 官方源码、完整内核配置合并与 kmods 源生成。
source "$(dirname "$0")/common.sh"
setup() {
    SRC="$TEST_TMP/immortalwrt"
    META="$TEST_TMP/official-abi"
    mkdir -p "$SRC/include" "$META" "$TEST_TMP/bin"
    SCRIPT="$ROOT/scripts/build/official-kernel-abi.sh"
    printf 'CONFIG_PACKAGE_qmodem=y\nCONFIG_KERNEL_DEBUG_INFO_BTF=n\nCONFIG_KERNEL_OLD=y\nCONFIG_ALL_KMODS=n\n# CONFIG_ALL_NONSHARED is not set\n' > "$SRC/.config"
    printf 'CONFIG_TARGET_rockchip_armv8=y\nCONFIG_KERNEL_DEBUG_INFO_BTF=y\n# CONFIG_KERNEL_OLD is not set\nCONFIG_ALL_KMODS=y\nCONFIG_ALL_NONSHARED=y\nCONFIG_PACKAGE_kselftests-bpf=m\nCONFIG_KERNEL_BUILD_USER="buildbot"\n' > "$META/official.config"
    printf 'CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_ariaboard_photonicat=y\n' > "$META/config.buildinfo"
    cat > "$SRC/include/kernel-defaults.mk" <<'KERNEL'
define Kernel/Configure/Default
	awk '/^(#[[:space:]]+)?CONFIG_KERNEL/{sub("CONFIG_KERNEL_","CONFIG_");print}' $(TOPDIR)/.config >> $(LINUX_DIR)/.config.target
	$(SCRIPT_DIR)/package-metadata.pl kconfig $(TMP_DIR)/.packageinfo $(TOPDIR)/.config $(KERNEL_PATCHVER) > $(LINUX_DIR)/.config.override
endef
KERNEL
    local imagebuilder=immortalwrt-imagebuilder-25.12-SNAPSHOT-rockchip-armv8.Linux-x86_64
    mkdir "$TEST_TMP/$imagebuilder"
    cp "$META/official.config" "$TEST_TMP/$imagebuilder/.config"
    export MOCK_OFFICIAL_ARCHIVE="$TEST_TMP/imagebuilder.tar.zst"
    tar --zstd -cf "$MOCK_OFFICIAL_ARCHIVE" -C "$TEST_TMP" "$imagebuilder/.config"
    export MOCK_OFFICIAL_SHA
    MOCK_OFFICIAL_SHA=$(sha256sum "$MOCK_OFFICIAL_ARCHIVE"); MOCK_OFFICIAL_SHA=${MOCK_OFFICIAL_SHA%% *}
    printf 'kernel-6.12.112~4ce22fc78523e0739bdb12c4ffdd2e26-r1.apk\n' > "$META/kernel-package"
}
test_merge_preserves_plugins_and_replaces_kernel_options() {
    ok bash "$SCRIPT" merge "$SRC" "$META"
    assert_has "$SRC/.config" 'CONFIG_PACKAGE_qmodem=y'
    assert_has "$SRC/.config" 'CONFIG_KERNEL_DEBUG_INFO_BTF=y'
    assert_has "$SRC/.config" '# CONFIG_KERNEL_OLD is not set'
    assert_has "$SRC/.config" 'CONFIG_ALL_KMODS=y'
    assert_has "$SRC/.config" 'CONFIG_KERNEL_BUILD_USER="buildbot"'
    assert_not_has "$SRC/.config" 'CONFIG_KERNEL_OLD=y'
    assert_same "$META/official.config" "$SRC/.config.official-kernel"
    assert_has "$SRC/include/kernel-defaults.mk" '$(TOPDIR)/.config.official-kernel >> $(LINUX_DIR)/.config.target'
    assert_has "$SRC/include/kernel-defaults.mk" 'kconfig $(TMP_DIR)/.packageinfo $(TOPDIR)/.config.official-kernel $(KERNEL_PATCHVER)'
    ok bash "$SCRIPT" merge "$SRC" "$META"
    assert_eq 1 "$(grep -c '^CONFIG_KERNEL_BUILD_USER=' "$SRC/.config")"
}
test_merge_changed_kernel_recipe_preserves_files() {
    rewrite "$SRC/include/kernel-defaults.mk" 'kconfig $(TMP_DIR)/.packageinfo' 'changed $(TMP_DIR)/.packageinfo'
    cp "$SRC/.config" "$TEST_TMP/config.before"
    cp "$SRC/include/kernel-defaults.mk" "$TEST_TMP/recipe.before"
    reject bash "$SCRIPT" merge "$SRC" "$META"
    assert_same "$SRC/.config" "$TEST_TMP/config.before"
    assert_same "$SRC/include/kernel-defaults.mk" "$TEST_TMP/recipe.before"
    assert_absent "$SRC/.config.official-kernel"
}
test_merge_preserves_userspace_selection_without_buildbot_test_packages() {
    ok bash "$SCRIPT" merge "$SRC" "$META"
    assert_has "$SRC/.config" '# CONFIG_ALL_NONSHARED is not set'
    assert_not_has "$SRC/.config" 'CONFIG_ALL_NONSHARED=y'
    assert_not_has "$SRC/.config" 'CONFIG_PACKAGE_kselftests-bpf='
    assert_has "$SRC/.config" 'CONFIG_ALL_KMODS=y'
    assert_has "$SRC/.config" 'CONFIG_KERNEL_DEBUG_INFO_BTF=y'
    assert_has "$SRC/.config" 'CONFIG_PACKAGE_qmodem=y'
    # 只阻止从官方 buildbot 配置带入选包开关，用户明确的选包仍保留。
    printf 'CONFIG_ALL_NONSHARED=y\nCONFIG_PACKAGE_kselftests-bpf=y\n' > "$SRC/.config"
    ok bash "$SCRIPT" merge "$SRC" "$META"
    assert_has "$SRC/.config" 'CONFIG_ALL_NONSHARED=y'
    assert_has "$SRC/.config" 'CONFIG_PACKAGE_kselftests-bpf=y'
}
pin_tools() {
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
  */sha256sums) value="$MOCK_OFFICIAL_SHA  immortalwrt-imagebuilder-25.12-SNAPSHOT-rockchip-armv8.Linux-x86_64.tar.zst" ;;
  */immortalwrt-imagebuilder-*.tar.zst) cp "$MOCK_OFFICIAL_ARCHIVE" "$output"; exit 0 ;;
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
}
test_pin_uses_official_revision_and_kernel_package() {
    pin_tools
    ok env PATH="$TEST_TMP/bin:$PATH" bash "$SCRIPT" pin "$SRC" "$META"
    assert_eq 'kernel-6.12.112~4ce22fc78523e0739bdb12c4ffdd2e26-r1.apk' "$(cat "$META/kernel-package")"
    assert_has "$OUT" '官方源码：r38263-84b665b5de'
    assert_has "$META/official.config" 'CONFIG_TARGET_rockchip_armv8=y'
    assert_absent "$META/immortalwrt-imagebuilder-25.12-SNAPSHOT-rockchip-armv8.Linux-x86_64.tar.zst"
}
test_pin_rejects_corrupt_imagebuilder() {
    pin_tools
    cp "$META/official.config" "$TEST_TMP/config.before"
    printf 'corrupt download' > "$MOCK_OFFICIAL_ARCHIVE"
    reject env PATH="$TEST_TMP/bin:$PATH" bash "$SCRIPT" pin "$SRC" "$META"
    assert_has "$ERR" '官方 ImageBuilder SHA256 不符'
    assert_same "$META/official.config" "$TEST_TMP/config.before"
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
run_tests "$@"
