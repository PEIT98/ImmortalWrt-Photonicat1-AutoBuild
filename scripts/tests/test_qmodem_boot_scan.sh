#!/bin/bash
# 在真实官方 init 脚本中验证网卡就绪等待及一次性 15 秒补扫。
source "$(dirname "$0")/common.sh"
FEED=$(realpath "${1:?需要 QModem Feed 目录}")
setup() {
    feed="$TEST_TMP/feed"
    init=application/qmodem/files/etc/init.d/qmodem_init
    mkdir -p "$feed/$(dirname "$init")" "$TEST_TMP/sys/class/net" \
        "$TEST_TMP/sys/bus/usb/devices" "$TEST_TMP/lock"
    git -C "$FEED" show "HEAD:$init" > "$feed/$init"
    cp "$feed/$init" "$TEST_TMP/original-init"
    patch="$ROOT/patches/qmodem/fix-qmodem-boot-scan.sh"
    ok sh "$patch" "$feed"
    cp "$feed/$init" "$TEST_TMP/init"
    # Source real functions, but substitute host-safe sysfs, client and lock paths.
    rewrite "$TEST_TMP/init" '. $IPKG_INSTROOT/lib/functions.sh' '# test library supplied by harness'
    rewrite "$TEST_TMP/init" '/sys/' "$TEST_TMP/sys/"
    rewrite "$TEST_TMP/init" '/var/lock' "$TEST_TMP/lock"
    rewrite "$TEST_TMP/init" '/usr/bin/modem_scanc' "$TEST_TMP/scanc"
    printf '0\n' > "$TEST_TMP/tick"
    : > "$TEST_TMP/calls"
    : > "$TEST_TMP/sleeps"
    cat > "$TEST_TMP/scanc" <<'SCANC'
#!/bin/sh
tick=$(cat "$TEST_BOOT_ROOT/tick")
case "$1" in
    status)
        [ "$tick" -ge "${TEST_DAEMON_READY_AT:-0}" ] &&
        [ "$tick" -lt "${TEST_DAEMON_STOP_AT:-9999}" ]
        ;;
    scan)
        printf '%s %s\n' "$tick" "$*" >> "$TEST_BOOT_ROOT/calls"
        ;;
    *) exit 1 ;;
esac
SCANC
    chmod +x "$TEST_TMP/scanc"
}
run_boot() {
    ok env TEST_BOOT_ROOT="$TEST_TMP" TEST_BOOT_INIT="$TEST_TMP/init" "$@" \
        timeout 15 sh "$ROOT/scripts/tests/fixtures/qmodem-boot-harness.sh"
}
calls() { assert_eq "$1" "$(cat "$TEST_TMP/calls")"; }
test_waits_for_modem_network_and_daemon_before_first_scan() {
    run_boot TEST_NET_READY_AT=3 TEST_DAEMON_READY_AT=5 TEST_RECOGNIZED_AT=10
    calls '5 scan usb 0'
    assert_eq 20 "$(cat "$TEST_TMP/tick")"
    assert_has "$TEST_TMP/log" 'USB modem recognized; skip boot rescan'
}
test_missing_modem_rescans_only_once_after_15_seconds() {
    run_boot
    calls $'0 scan usb 0\n15 scan usb 0'
    assert_eq 15 "$(cat "$TEST_TMP/tick")"
    assert_has "$TEST_TMP/log" 'queued one boot rescan'
}
test_recognized_modem_skips_second_scan() {
    run_boot TEST_RECOGNIZED_AT=0
    calls '0 scan usb 0'
}
test_custom_scan_delay_and_interface_name_are_preserved() {
    run_boot TEST_SCAN_DELAY=7 TEST_NET_NAME=usb99
    calls $'0 scan usb 7\n22 scan usb 0'
}
test_no_modem_network_stops_after_bounded_wait() {
    run_boot TEST_NO_NETWORK=1 TEST_OTHER_NETWORK=1
    calls ''
    assert_eq 60 "$(cat "$TEST_TMP/tick")"
    assert_has "$TEST_TMP/log" 'stopped after 60 seconds'
}
test_disabled_scanning_and_manual_mode_are_respected() {
    run_boot TEST_DISABLE_AT=0
    calls ''
    assert_eq 0 "$(cat "$TEST_TMP/tick")"
    run_boot TEST_BLOCK_AUTO=1
    calls ''
}
test_disabling_or_stopping_during_wait_prevents_rescan() {
    run_boot TEST_DISABLE_AT=15
    calls '0 scan usb 0'
    : > "$TEST_TMP/calls"
    printf '0\n' > "$TEST_TMP/tick"
    run_boot TEST_DAEMON_STOP_AT=15
    calls '0 scan usb 0'
}
test_stale_configuration_does_not_count_as_recognition() {
    run_boot TEST_RECOGNIZED_AT=0 TEST_STALE_PATH=1
    calls $'0 scan usb 0\n15 scan usb 0'
}
test_one_recognized_modem_does_not_hide_another_missing_one() {
    run_boot TEST_RECOGNIZED_AT=0 TEST_SECOND_NETWORK=1
    calls $'0 scan usb 0\n15 scan usb 0'
}
test_existing_worker_lock_prevents_duplicate_loop() {
    run_boot TEST_HOLD_LOCK=1
    calls ''
    assert_eq 0 "$(cat "$TEST_TMP/tick")"
}
test_patch_is_idempotent_and_preserves_pcie_scan() {
    cp "$feed/$init" "$TEST_TMP/once"
    ok sh "$patch" "$feed"
    assert_same "$feed/$init" "$TEST_TMP/once"
    assert_has "$feed/$init" '_queue_boot_scan pcie'
    assert_has "$feed/$init" 'config_foreach _try_usb_device modem-device'
    assert_eq 1 "$(grep -c '^_queue_ready_usb_scan()$' "$feed/$init")"
}
test_changed_upstream_layout_is_rejected_without_writing() {
    cp "$TEST_TMP/original-init" "$feed/$init"
    rewrite "$feed/$init" '_queue_boot_scan usb' '_queue_other_scan usb'
    cp "$feed/$init" "$TEST_TMP/before"
    reject sh "$patch" "$feed"
    assert_same "$feed/$init" "$TEST_TMP/before"
}
test_changed_existing_fragment_is_rejected_without_writing() {
    rewrite "$feed/$init" 'while [ "$attempts" -lt 60 ]; do' 'while [ "$attempts" -lt 61 ]; do'
    cp "$feed/$init" "$TEST_TMP/before"
    reject sh "$patch" "$feed"
    assert_same "$feed/$init" "$TEST_TMP/before"
}
run_tests "$@"
