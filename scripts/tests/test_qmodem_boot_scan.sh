#!/bin/bash
# 用模拟时钟检查网卡等待、USB/PCIe 全扫描及一次条件补扫。
source "$(dirname "$0")/common.sh"
FEED=$(realpath "${1:?需要 QModem Feed 目录}")
setup() {
    feed="$TEST_TMP/feed"
    init="$feed/application/qmodem/files/etc/init.d/qmodem_init"
    fragment="$feed/application/qmodem/files/usr/share/qmodem/fixes/boot-scan.sh"
    mkdir -p "$(dirname "$init")"
    git -C "$FEED" show HEAD:application/qmodem/files/etc/init.d/qmodem_init > "$init"
    patch="$ROOT/patches/qmodem/fix-qmodem-boot-scan.sh"
    ok sh "$patch" "$feed"
    source "$fragment"
    pwrt_qmodem_net_signature() { mock_net_signature; }
    pwrt_qmodem_scan_all() { mock_scan_all; }
    mock_seconds=0
    MOCK_COUNT=1
    MOCK_PORT=/dev/null
    MOCK_BLOCK=0
    MOCK_DELAY=0
    MOCK_LAYOUT=normal
    MOCK_SCAN_RC=0
    : > "$TEST_TMP/scans"
    : > "$TEST_TMP/log"
}
config_load() { :; }
config_get() {
    local output_name=$1 section=$2 option=$3 result=${4:-}
    case "$section:$option" in
        main:start_delay) result=$MOCK_DELAY ;;
        main:block_auto_probe) result=$MOCK_BLOCK ;;
        main:enable_usb_scan|main:enable_pcie_scan) result=1 ;;
        one:name) result=fm350-gl ;;
        two:name) result=rm520n-gl ;;
        one:state|two:state) result=enabled ;;
        one:at_port|two:at_port) result=$MOCK_PORT ;;
        one:network) result=eth2 ;;
        two:network) result=wwan0 ;;
    esac
    printf -v "$output_name" '%s' "$result"
}
config_foreach() {
    [[ $2 == modem-device ]] || return 0
    (( MOCK_COUNT >= 1 )) && "$1" one
    (( MOCK_COUNT >= 2 )) && "$1" two
    return 0
}
sleep() { mock_seconds=$((mock_seconds + $1)); }
logger() { printf '%s\n' "$*" >> "$TEST_TMP/log"; }
mock_net_signature() {
    case "$MOCK_LAYOUT" in
        absent) return 0 ;;
        late) (( mock_seconds >= 20 )) || return 0 ;;
    esac
    printf '%s\n' eth2=/sys/devices/usb1/1-1
    [[ $MOCK_LAYOUT != multi ]] || printf '%s\n' wwan0=/sys/devices/pci/0002:21:00.0
    return 0
}
mock_scan_all() {
    printf 'scan all at %s\n' "$mock_seconds" >> "$TEST_TMP/scans"
    return "$MOCK_SCAN_RC"
}
test_identified_modem_skips_retry_after_stable_network_wait() {
    pwrt_qmodem_boot_scan
    assert_eq 'scan all at 18' "$(cat "$TEST_TMP/scans")"
    assert_eq 33 "$mock_seconds"
}
test_late_network_waits_for_three_stable_seconds() {
    MOCK_LAYOUT=late
    pwrt_qmodem_boot_scan
    assert_eq 'scan all at 23' "$(cat "$TEST_TMP/scans")"
}
test_unidentified_modem_retries_once_after_fifteen_seconds() {
    MOCK_COUNT=0
    pwrt_qmodem_boot_scan
    assert_eq $'scan all at 18\nscan all at 33' "$(cat "$TEST_TMP/scans")"
}
test_partial_identification_still_retries_all_buses() {
    MOCK_LAYOUT=multi
    pwrt_qmodem_boot_scan
    assert_eq $'scan all at 18\nscan all at 33' "$(cat "$TEST_TMP/scans")"
    MOCK_COUNT=2
    reject pwrt_qmodem_need_retry
}
test_stale_at_port_does_not_count_as_identified() {
    MOCK_PORT=/dev/not-a-qmodem-port
    pwrt_qmodem_boot_scan
    assert_eq $'scan all at 18\nscan all at 33' "$(cat "$TEST_TMP/scans")"
}
test_no_network_has_bounded_wait_and_one_retry() {
    MOCK_LAYOUT=absent
    pwrt_qmodem_boot_scan
    assert_eq $'scan all at 30\nscan all at 45' "$(cat "$TEST_TMP/scans")"
}
test_configured_start_delay_is_preserved() {
    MOCK_DELAY=40
    pwrt_qmodem_boot_scan
    assert_eq 'scan all at 43' "$(cat "$TEST_TMP/scans")"
}
test_failed_scan_request_still_retries_once() {
    MOCK_SCAN_RC=2
    pwrt_qmodem_boot_scan
    assert_eq $'scan all at 18\nscan all at 33' "$(cat "$TEST_TMP/scans")"
}
load_patched_init() {
    sed '/^\. \$IPKG_INSTROOT\/lib\/functions.sh$/d' "$init" > "$TEST_TMP/init.sh"
    source "$TEST_TMP/init.sh"
    _prepare_pcie_slot() { :; }
    _mk_rundir() { :; }
    _start_scand() { printf 'scand\n' >> "$TEST_TMP/scans"; }
    _try_vendor_preset_usb() { printf 'preset usb\n' >> "$TEST_TMP/scans"; }
    _try_vendor_preset_pcie() { printf 'preset pcie\n' >> "$TEST_TMP/scans"; }
    _scan_usb() { printf 'scan usb\n' >> "$TEST_TMP/scans"; }
    _scan_pcie() { printf 'scan pcie\n' >> "$TEST_TMP/scans"; }
}
test_boot_guard_avoids_duplicate_scans_and_preserves_manual_start() {
    load_patched_init
    PWRT_QMODEM_BOOT_SCAN=1 start_service
    assert_eq scand "$(cat "$TEST_TMP/scans")"
    : > "$TEST_TMP/scans"
    start_service
    assert_eq $'scand\npreset pcie\npreset usb\nscan usb\nscan pcie' "$(cat "$TEST_TMP/scans")"
}
test_block_auto_probe_skips_boot_worker() {
    load_patched_init
    start() { printf 'start\n' >> "$TEST_TMP/scans"; }
    MOCK_BLOCK=1
    boot
    assert_eq start "$(cat "$TEST_TMP/scans")"
    [[ ! -v PWRT_QMODEM_BOOT_SCAN ]] || fail 'boot guard leaked'
}
test_patch_is_idempotent_and_keeps_official_dialing() {
    cp "$init" "$TEST_TMP/once"
    ok sh "$patch" "$feed"
    assert_same "$init" "$TEST_TMP/once"
    assert_same "$fragment" "$ROOT/patches/qmodem/boot-scan.sh"
    assert_not_has "$init" 'modem_scan.sh scan'
    assert_has "$fragment" '/usr/bin/modem_scanc scan all'
    assert_absent "$feed/application/qmodem/files/usr/share/qmodem/modem_dial.sh"
}
test_patch_rejects_upstream_layout_changes_without_writing() {
    git -C "$FEED" show HEAD:application/qmodem/files/etc/init.d/qmodem_init > "$init"
    rewrite "$init" 'boot() {' 'boot_changed() {'
    cp "$init" "$TEST_TMP/before"
    reject sh "$patch" "$feed"
    assert_same "$init" "$TEST_TMP/before"
}
run_tests "$@"
