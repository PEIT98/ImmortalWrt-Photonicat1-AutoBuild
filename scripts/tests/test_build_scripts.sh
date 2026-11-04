#!/bin/bash
# Protect configuration inheritance and failed-patch rollback during language changes.
source "$(dirname "$0")/common.sh"
setup() { :; }
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
