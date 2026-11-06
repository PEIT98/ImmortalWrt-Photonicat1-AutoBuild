#!/bin/bash
# 编译真实 QM 源码，复现系统时间跳变及任务去重后的扫描等待。
source "$(dirname "$0")/common.sh"
FEED=$(realpath "${1:?需要 QModem Feed 目录}")
setup() {
    local src="$TEST_TMP/feed/application/modem_scan/src"
    mkdir -p "$src" "$TEST_TMP/bin"
    # Always replay the selected official commit, even if the Feed is patched already.
    git -C "$FEED" show HEAD:application/modem_scan/src/modem_scand.c > "$src/modem_scand.c"
    git -C "$FEED" show HEAD:application/modem_scan/src/modem_scan_common.h > "$src/modem_scan_common.h"
    mkdir -p "$TEST_TMP/feed/application/qmodem/files/etc/init.d"
    git -C "$FEED" show HEAD:application/qmodem/files/etc/init.d/qmodem_init > "$TEST_TMP/feed/application/qmodem/files/etc/init.d/qmodem_init"
    mkdir -p "$TEST_TMP/feed/application/qmodem/files/usr/share/qmodem"
    git -C "$FEED" show HEAD:application/qmodem/files/usr/share/qmodem/modem_dial.sh > "$TEST_TMP/feed/application/qmodem/files/usr/share/qmodem/modem_dial.sh"
    scanner="$src/modem_scand.c"
    patch="$ROOT/patches/qmodem/fix-qmodem-monotonic-clock.sh"
    # Queue tests must not read or change the host UCI configuration.
    printf '#!/bin/sh\nexit 1\n' > "$TEST_TMP/bin/uci"
    chmod +x "$TEST_TMP/bin/uci"
}
compile_scanner() {
    local variant=$1
    local -a cppflags ldflags extra=()
    read -r -a cppflags <<< "${QMODEM_TEST_CPPFLAGS:-$(pkg-config --cflags json-c)}"
    read -r -a ldflags <<< "${QMODEM_TEST_LDFLAGS:-$(pkg-config --libs json-c)}"
    [[ $variant == patched ]] && extra+=(-DTEST_PATCHED)
    ok "${CC:-cc}" -std=c99 -D_GNU_SOURCE -Wall -Wextra -Wno-format-truncation \
        "${cppflags[@]}" "${extra[@]}" "-DQMODEM_SCANNER_SOURCE=\"$scanner\"" \
        "$ROOT/scripts/tests/fixtures/qmodem-clock-harness.c" \
        "${ldflags[@]}" -lpthread -o "$TEST_TMP/scanner"
}
apply_patch() { ok sh "$patch" "$TEST_TMP/feed"; }
run_clock_case() { ok env PATH="$TEST_TMP/bin:$PATH" timeout 15 "$TEST_TMP/scanner" "$1"; }
test_upstream_reproduces_clock_rollback_with_deduplicated_add() {
    compile_scanner original
    reject env PATH="$TEST_TMP/bin:$PATH" timeout 15 "$TEST_TMP/scanner" backward
    assert_has "$ERR" 'delayed scan remains blocked after clock rollback'
}
test_patched_queue_handles_backward_forward_normal_and_immediate() {
    apply_patch
    compile_scanner patched
    local scenario
    for scenario in backward forward normal immediate condition; do run_clock_case "$scenario"; done
    assert_not_has "$scanner" 'time(NULL)'
}
test_patch_is_idempotent_and_keeps_other_sources() {
    cp "$scanner" "$TEST_TMP/before"
    apply_patch
    cp "$scanner" "$TEST_TMP/once"
    apply_patch
    assert_same "$scanner" "$TEST_TMP/once"
    assert_same "${scanner%/*}/modem_scan_common.h" "$FEED/application/modem_scan/src/modem_scan_common.h"
}
test_patch_rejects_changed_clock_layout_without_writing() {
    rewrite "$scanner" 'e->not_before = time(NULL) + delay_sec;' 'e->not_before = 0;'
    cp "$scanner" "$TEST_TMP/before"
    reject sh "$patch" "$TEST_TMP/feed"
    assert_same "$scanner" "$TEST_TMP/before"
}
test_runtime_check_allows_only_the_expected_qmodem_fixes() {
    local feed="$TEST_TMP/feed" check="$ROOT/scripts/checks/verify-qmodem-feeds.sh"
    mkdir -p "$TEST_TMP/root/feeds" "$feed/application/qmodem"
    printf '# unchanged dial configuration\n' > "$feed/application/qmodem/config"
    git -C "$feed" init -q
    git -C "$feed" add application
    git -C "$feed" -c user.name=Test -c user.email=test@example.invalid commit -qm baseline
    ln -s "$feed" "$TEST_TMP/root/feeds/qmodem"
    # A missed build hook must not silently ship the unpatched scanner.
    reject bash "$check" runtime "$TEST_TMP/root"
    apply_patch
    ok bash "$check" runtime "$TEST_TMP/root"
    local dial="$feed/application/qmodem/files/usr/share/qmodem/modem_dial.sh"
    cp "$dial" "$TEST_TMP/valid-dial"
    printf '\n# unexpected dial change\n' >> "$dial"
    reject bash "$check" runtime "$TEST_TMP/root"
    cp "$TEST_TMP/valid-dial" "$dial"
    cp "$scanner" "$TEST_TMP/valid-scanner"
    printf '\n/* unexpected scanner change */\n' >> "$scanner"
    reject bash "$check" runtime "$TEST_TMP/root"
    cp "$TEST_TMP/valid-scanner" "$scanner"
    cp "$feed/application/qmodem/files/etc/init.d/qmodem_init" "$TEST_TMP/valid-init"
    printf '\n# unexpected init change\n' >> "$feed/application/qmodem/files/etc/init.d/qmodem_init"
    reject bash "$check" runtime "$TEST_TMP/root"
    cp "$TEST_TMP/valid-init" "$feed/application/qmodem/files/etc/init.d/qmodem_init"
    printf '# unexpected dial change\n' >> "$feed/application/qmodem/config"
    reject bash "$check" runtime "$TEST_TMP/root"
    git -C "$feed" checkout -- application/qmodem/config
    printf 'unexpected file\n' > "$feed/application/modem_scan/src/extra.c"
    reject bash "$check" runtime "$TEST_TMP/root"
    rm "$feed/application/modem_scan/src/extra.c"
    printf 'unexpected file\n' > "$feed/application/qmodem/files/usr/share/qmodem/extra.sh"
    reject bash "$check" runtime "$TEST_TMP/root"
    rm "$feed/application/qmodem/files/usr/share/qmodem/extra.sh"
    ok bash "$check" runtime "$TEST_TMP/root"
}
run_tests "$@"
