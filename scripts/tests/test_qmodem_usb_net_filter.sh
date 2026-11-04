#!/bin/bash
# 直接验证官方扫描函数；变异检查仅修改临时副本，不改写 Feed 源码。
source "$(dirname "$0")/common.sh"
FEED=$(realpath "${1:?需要 QModem Feed 目录}")
setup() {
    scanner="$TEST_TMP/modem_scand.c"
    cp "$FEED/application/modem_scan/src/modem_scand.c" "$scanner"
}
compile_scan() {
    cat "$ROOT/scripts/tests/fixtures/usb-scan-harness.c" > "$TEST_TMP/unit.c"
    awk 'BEGIN {RS="\0";ORS=""} {
        a=index($0,"static int interface_allowed(");
        b=index(substr($0,a),"\nstatic void apply_option_driver(");
        if(!a||!b)exit 1;
        print substr($0,a,b-1);
        a=index($0,"static void scan_usb_slot(");
        b=index($0,"\nstatic void scan_associated_usb(");
        if(!a||b<=a)exit 1;
        print substr($0,a,b-a)
    }' "$scanner" >> "$TEST_TMP/unit.c"
    cat "$ROOT/scripts/tests/fixtures/usb-scan-cases.c" >> "$TEST_TMP/unit.c"
    ok "${CC:-cc}" -std=c99 -D_GNU_SOURCE -Wall -Wextra -Werror -Wno-format-truncation "$TEST_TMP/unit.c" -o "$TEST_TMP/scanner"
}
test_official_scan_keeps_network_at_and_voice_rules() {
    compile_scan
    ok "$TEST_TMP/scanner"
    assert_has "$OUT" '12 组 USB 扫描回归通过'
    assert_same "$scanner" "$FEED/application/modem_scan/src/modem_scand.c"
}
test_regression_detects_relaxed_at_whitelist() {
    rewrite "$scanner" 'if (!interface_allowed(&rule, if_port)) {' 'if (interface_allowed(&rule, if_port) && 0) {'
    compile_scan
    reject "$TEST_TMP/scanner"
    assert_has "$ERR" '诊断串口的白名单行为改变'
}
test_regression_detects_network_filtered_by_at_whitelist() {
    local anchor=$'\t\tsnprintf(path, sizeof(path), "%s/%s", slot_path, de->d_name);\n'
    rewrite "$scanner" "$anchor" "$anchor"$'\t\tif (!interface_allowed(&rule, if_port)) continue;\n'
    compile_scan
    reject "$TEST_TMP/scanner"
    assert_has "$ERR" '网卡被 AT 白名单过滤'
}
run_tests "$@"
