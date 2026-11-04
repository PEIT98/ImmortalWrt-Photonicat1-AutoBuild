#!/bin/bash
source "$(dirname "$0")/common.sh"
FEED=$(realpath "${1:?需要 QModem Feed 目录}")
source "$ROOT/scripts/lib/qmodem-usb-layout.sh"
setup() {
    feed="$TEST_TMP/feed"; scanner="$feed/application/modem_scan/src/modem_scand.c"
    mkdir -p "$(dirname "$scanner")"; cp "$FEED/application/modem_scan/src/modem_scand.c" "$scanner"
    patch="$ROOT/scripts/patches/fix-qmodem-usb-net-filter.sh"
}
usb_edit() {
    EDIT_OLD=$1 EDIT_NEW=$2 awk '
BEGIN {RS="\0"; ORS=""; a=ENVIRON["START"];z=ENVIRON["END"];old=ENVIRON["EDIT_OLD"];new=ENVIRON["EDIT_NEW"]}
{start=index($0,a); end=index($0,z); body=substr($0,start,end-start); p=index(body,old); if(!p)exit 1; body=substr(body,1,p-1) new substr(body,p+length(old)); printf "%s%s%s",substr($0,1,start-1),body,substr($0,end)}' "$scanner" > "$TEST_TMP/edit"
    cp "$TEST_TMP/edit" "$scanner"
}
compile_scan() {
    cat "$ROOT/scripts/tests/fixtures/usb-scan-harness.c" > "$TEST_TMP/unit.c"
    awk 'BEGIN {RS="\0";ORS=""} {a=index($0,"static int interface_allowed(");b=index(substr($0,a),"\nstatic void apply_option_driver(");if(!a||!b)exit 1; print substr($0,a,b-1);a=index($0,ENVIRON["START"]);b=index($0,ENVIRON["END"]);if(!a||b<=a)exit 1; print substr($0,a,b-a)}' "$scanner" >> "$TEST_TMP/unit.c"
    cat "$ROOT/scripts/tests/fixtures/usb-scan-cases.c" >> "$TEST_TMP/unit.c"
    ok "${CC:-cc}" -std=c99 -D_GNU_SOURCE -Wall -Wextra -Werror -Wno-format-truncation "$TEST_TMP/unit.c" -o "$TEST_TMP/scanner"
}
test_real_scan_and_idempotence() {
    cp "$scanner" "$TEST_TMP/before"
    ok sh "$patch" "$feed"; cp "$scanner" "$TEST_TMP/once"
    ok sh "$patch" "$feed"; assert_same "$scanner" "$TEST_TMP/once"
    compile_scan; ok "$TEST_TMP/scanner"; assert_has "$OUT" '12 组 USB 扫描回归通过'
}
test_drift_rejected_without_write() {
    rewrite "$scanner" 'if (!interface_allowed(&rule, if_port)) {' 'if (0) {'
    cp "$scanner" "$TEST_TMP/before"
    reject sh "$patch" "$feed"; assert_same "$scanner" "$TEST_TMP/before"
}
test_legacy_and_original_migration() {
    ok sh "$patch" "$feed"
    if grep -Fq photonicat-usb-net-first "$scanner"; then
        usb_edit "$NETWORK_FIRST" ''
        usb_edit "$SERIAL_END" $'\t\t\tsl_free(&ttys);\n'"$NETWORK_TAIL"
    else
        # Reconstruct the old network-after-global-rule layout from the real AT branch.
        guard=$'\t\t\t/* The include rule filters AT ports, not network interfaces. */\n\t\t\tif (!interface_allowed(&rule, if_port)) {\n\t\t\t\tlog_msg(LOG_L_DEBUG, "skip usb %s AT interface %s by modem_port_rule", slot, if_port);\n\t\t\t\tcontinue;\n\t\t\t}\n'
        usb_edit "$guard" ''
        usb_edit "$SERIAL" "$ORIGINAL"
    fi
    cp "$scanner" "$TEST_TMP/original"
    compile_scan; reject "$TEST_TMP/scanner"; assert_has "$ERR" '网卡被 AT 白名单过滤'
    ok sh "$patch" "$feed"; cp "$scanner" "$TEST_TMP/expected"
    compile_scan; ok "$TEST_TMP/scanner"
    cp "$TEST_TMP/original" "$scanner"; usb_edit "$ORIGINAL" "$LEGACY_PATCHED"
    ok sh "$patch" "$feed"; assert_same "$scanner" "$TEST_TMP/expected"
}
run_tests "$@"
