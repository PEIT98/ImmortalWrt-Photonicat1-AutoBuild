#!/bin/bash
source "$(dirname "$0")/common.sh"
setup() {
    app="$TEST_TMP/feeds/luci/applications/luci-app-weechat/Makefile"
    provider="$TEST_TMP/feeds/packages/net/weechat/Makefile"
    mkdir -p "$(dirname "$app")" "$(dirname "$provider")"
    printf '# Apache-2.0\nLUCI_TITLE:=WeeChat\nLUCI_DEPENDS:=+luci-base +weechat +rpcd-mod-ucode\n' > "$app"
    cp "$app" "$TEST_TMP/original"
    printf 'define Package/weechat-minimal\n DEFAULT_VARIANT:=1\n PROVIDES:=weechat\nendef\n' > "$provider"
    patch="$ROOT/scripts/patches/packages/fix-weechat-provider.sh"
}
test_provider_once() {
    ok sh "$patch" "$TEST_TMP"
    assert_has "$app" 'LUCI_DEPENDS:=+luci-base +weechat-minimal +rpcd-mod-ucode'
    cp "$app" "$TEST_TMP/once"
    ok sh "$patch" "$TEST_TMP"
    assert_same "$app" "$TEST_TMP/once"
}
test_fixed_upstream() {
    sed -i 's/+weechat /+weechat-full /' "$app"
    cp "$app" "$TEST_TMP/once"
    ok sh "$patch" "$TEST_TMP"
    assert_same "$app" "$TEST_TMP/once"
}
test_missing_provider() {
    rm "$provider"
    reject sh "$patch" "$TEST_TMP"
    assert_same "$app" "$TEST_TMP/original"
}
test_native_word_reads() {
    assert_has "$ROOT/photonicat1.config" 'CONFIG_PACKAGE_coreutils-od=y'
    assert_has "$ROOT/scripts/checks/verify-config.sh" CONFIG_PACKAGE_coreutils-od
    assert_not_has "$ROOT/photonicat1.config" CONFIG_BUSYBOX_CONFIG_HEXDUMP
    assert_not_has "$ROOT/scripts/checks/verify-config.sh" CONFIG_BUSYBOX_CONFIG_HEXDUMP
    sed '$d' "$ROOT/files/usr/libexec/swrt-autogrow" > "$TEST_TMP/words.sh"
    printf '\000\000\000\000\357\276\255\336\000\000\000\000\210\167\146\125\104\063\042\021\000\000\000\000\000\000\000\000\000\000\000\000' > "$TEST_TMP/block"
    printf '\nu32 "$1" 4\nu64 "$1" 12\n' >> "$TEST_TMP/words.sh"
    ok sh "$TEST_TMP/words.sh" "$TEST_TMP/block"
    assert_eq $'3735928559\n1234605616436508552' "$(cat "$OUT")"
    printf '\nu64 "$1" 28\n' >> "$TEST_TMP/words.sh"
    reject sh "$TEST_TMP/words.sh" "$TEST_TMP/block"
}
run_tests "$@"
