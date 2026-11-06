#!/bin/bash
# 检查真实上游初始化脚本的 USB 范围、AT 工具默认值及补丁失败保护。
source "$(dirname "$0")/common.sh"
FEED=$(realpath "${1:?需要 QModem Feed 目录}")
setup() {
    feed="$TEST_TMP/feed"
    init="$feed/application/qmodem/files/etc/init.d/qmodem_init"
    hotplug="$feed/application/qmodem/files/etc/hotplug.d/net/20-modem-net"
    defaults="$feed/application/qmodem/files/etc/uci-defaults/99-qmodem-usb"
    patch="$ROOT/patches/qmodem/fix-qmodem-usb.sh"
    local path
    for path in application/qmodem/files/etc/init.d/qmodem_init application/qmodem/files/etc/hotplug.d/net/20-modem-net; do
        mkdir -p "$feed/$(dirname "$path")"
        git -C "$FEED" show "HEAD:$path" > "$feed/$path"
    done
    cp "$init" "$TEST_TMP/official-init"
    cp "$hotplug" "$TEST_TMP/official-hotplug"
    ok sh "$patch" "$feed"
    export PWRT_QMODEM_TEST_STATE="$TEST_TMP/state" PWRT_QMODEM_TEST_LOG="$TEST_TMP/events"
    mkdir -p "$PWRT_QMODEM_TEST_STATE" "$TEST_TMP/bin"
    : > "$PWRT_QMODEM_TEST_LOG"
    printf 'main\n' > "$PWRT_QMODEM_TEST_STATE/qmodem.main"
    printf '0\n' > "$PWRT_QMODEM_TEST_STATE/qmodem.main.enable_dial"
    printf '0\n' > "$PWRT_QMODEM_TEST_STATE/qmodem.main.block_auto_probe"
    printf 'my.apn\n' > "$PWRT_QMODEM_TEST_STATE/qmodem.6_1.apn"
    printf '7\n' > "$PWRT_QMODEM_TEST_STATE/qmodem.6_1.pdp_index"
    printf 'eth2\n' > "$PWRT_QMODEM_TEST_STATE/qmodem.6_1.network"
    printf '/dev/ttyUSB1\n' > "$PWRT_QMODEM_TEST_STATE/qmodem.6_1.at_port"
    cat > "$TEST_TMP/bin/uci" <<'MOCK'
#!/bin/sh
set -eu
[ "$1" != -q ] || shift
action=$1; key=$2
case "$action" in
    get) cat "$PWRT_QMODEM_TEST_STATE/$key" 2>/dev/null ;;
    set) printf '%s\n' "${key#*=}" > "$PWRT_QMODEM_TEST_STATE/${key%%=*}" ;;
    delete) rm "$PWRT_QMODEM_TEST_STATE/$key" ;;
    commit) [ "$key" = qmodem ] && touch "$PWRT_QMODEM_TEST_STATE/committed" ;;
    *) exit 2 ;;
esac
MOCK
    cat > "$TEST_TMP/bin/lsusb" <<'MOCK'
#!/bin/sh
printf 'Bus 001 Device 001: ID %s modem\n' "$PWRT_QMODEM_TEST_USB_ID"
MOCK
    cat > "$TEST_TMP/bin/modem_scan.sh" <<'MOCK'
#!/bin/sh
printf '%s %s\n' "${0##*/}" "$*" >> "$PWRT_QMODEM_TEST_LOG"
MOCK
    cp "$TEST_TMP/bin/modem_scan.sh" "$TEST_TMP/bin/modem_scanc"
    printf '#!/bin/sh\nexit 0\n' > "$TEST_TMP/bin/logger"
    chmod +x "$TEST_TMP/bin/"*
    export PATH="$TEST_TMP/bin:$PATH" PWRT_QMODEM_TEST_USB_ID=0e8d:7127
}
apply_defaults() { ok sh "$defaults"; }
test_usb_defaults_preserve_apn_ports_and_dial_switch() {
    cp -a "$PWRT_QMODEM_TEST_STATE" "$TEST_TMP/before"
    apply_defaults
    assert_eq 15 "$(uci get qmodem.main.start_delay)"
    assert_eq 1 "$(uci get qmodem.main.enable_usb_scan)"
    assert_eq 0 "$(uci get qmodem.main.enable_pcie_scan)"
    assert_eq 0 "$(uci get qmodem.main.try_preset_pcie)"
    assert_eq 1 "$(uci get qmodem.main.at_tool)"
    local path
    for path in "$TEST_TMP/before/"*; do
        assert_same "$path" "$PWRT_QMODEM_TEST_STATE/${path##*/}"
    done
    assert_file "$PWRT_QMODEM_TEST_STATE/committed"
}
test_tdtech_uses_default_at_tool_without_disabling_dial() {
    export PWRT_QMODEM_TEST_USB_ID=3466:3301
    printf '1\n' > "$PWRT_QMODEM_TEST_STATE/qmodem.main.enable_dial"
    apply_defaults
    assert_absent "$PWRT_QMODEM_TEST_STATE/qmodem.main.at_tool"
    assert_eq 1 "$(uci get qmodem.main.enable_dial)"
}
test_missing_main_keeps_defaults_pending_without_changes() {
    rm "$PWRT_QMODEM_TEST_STATE/qmodem.main"
    reject sh "$defaults"
    assert_absent "$PWRT_QMODEM_TEST_STATE/qmodem.main.start_delay"
    assert_absent "$PWRT_QMODEM_TEST_STATE/committed"
}
config_load() { :; }
config_foreach() { :; }
config_get() {
    local destination=$1 section=$2 option=$3 value
    value=$(uci -q get "qmodem.$section.$option") || value=${4:-}
    printf -v "$destination" '%s' "$value"
}
test_native_boot_uses_delayed_usb_scans_without_custom_worker() {
    apply_defaults
    sed '/^\. \$IPKG_INSTROOT\/lib\/functions.sh$/d' "$init" > "$TEST_TMP/init-under-test"
    rewrite "$TEST_TMP/init-under-test" /usr/share/qmodem/modem_scan.sh "$TEST_TMP/bin/modem_scan.sh"
    rewrite "$TEST_TMP/init-under-test" /usr/bin/modem_scanc "$TEST_TMP/bin/modem_scanc"
    source "$TEST_TMP/init-under-test"
    _start_scand() { printf 'scand\n' >> "$PWRT_QMODEM_TEST_LOG"; }
    _try_vendor_preset_usb() { printf 'preset usb\n' >> "$PWRT_QMODEM_TEST_LOG"; }
    _try_vendor_preset_pcie() { printf 'preset pcie\n' >> "$PWRT_QMODEM_TEST_LOG"; }
    sleep() { printf 'sleep %s\n' "$1" >> "$PWRT_QMODEM_TEST_LOG"; }
    logger() { :; }
    start() { start_service; }
    boot
    wait
    assert_has "$PWRT_QMODEM_TEST_LOG" 'scand'
    assert_has "$PWRT_QMODEM_TEST_LOG" 'preset usb'
    assert_has "$PWRT_QMODEM_TEST_LOG" 'sleep 15'
    assert_has "$PWRT_QMODEM_TEST_LOG" 'modem_scan.sh scan usb'
    assert_has "$PWRT_QMODEM_TEST_LOG" 'modem_scanc scan usb'
    assert_not_has "$PWRT_QMODEM_TEST_LOG" 'pcie'
    assert_not_has "$PWRT_QMODEM_TEST_LOG" 'scan all'
    assert_not_has "$init" 'PWRT_QMODEM_BOOT_SCAN'
    assert_absent "$feed/application/qmodem/files/usr/share/qmodem/fixes/boot-scan.sh"
}
run_hotplug() {
    local bus=$1 slot=$2 marker=$3 interface=$4 sysroot="$TEST_TMP/sys" devpath
    devpath="/bus/$bus/devices/$slot/net/$interface"
    mkdir -p "$sysroot$devpath"
    printf '1\n' > "$sysroot/bus/$bus/devices/$slot/$marker"
    ln -s "$sysroot/bus/$bus/devices/$slot" "$sysroot$devpath/device"
    cp "$hotplug" "$TEST_TMP/hotplug-under-test"
    rewrite "$TEST_TMP/hotplug-under-test" /usr/share/qmodem/modem_scan.sh "$TEST_TMP/bin/modem_scan.sh"
    ok env QMODEM_SYSFS_ROOT="$sysroot" DEVPATH="$devpath" INTERFACE="$interface" ACTION=add \
        sh -c '. "$1"; wait' sh "$TEST_TMP/hotplug-under-test"
}
test_pcie_wifi_hotplug_does_not_queue_modem_probe() {
    run_hotplug pci 0002:21:00.0 vendor wlan0
    assert_eq '' "$(cat "$PWRT_QMODEM_TEST_LOG")"
}
test_usb_modem_hotplug_keeps_official_add_path() {
    run_hotplug usb 6-1 idVendor eth2
    assert_has "$PWRT_QMODEM_TEST_LOG" 'modem_scan.sh add 6-1 usb 8'
}
test_patch_is_idempotent_and_keeps_native_init_logic() {
    cp "$init" "$TEST_TMP/once-init"
    cp "$hotplug" "$TEST_TMP/once-hotplug"
    ok sh "$patch" "$feed"
    assert_same "$init" "$TEST_TMP/once-init"
    assert_same "$hotplug" "$TEST_TMP/once-hotplug"
    cp "$TEST_TMP/official-init" "$TEST_TMP/expected-init"
    rewrite "$TEST_TMP/expected-init" 'modem_scan.sh scan >' 'modem_scan.sh scan usb >'
    assert_same "$init" "$TEST_TMP/expected-init"
    assert_same "$defaults" "$ROOT/patches/qmodem/usb-defaults.sh"
    [[ -x $defaults ]] || fail 'UCI defaults must be executable'
    assert_absent "$feed/application/qmodem/files/usr/share/qmodem/modem_dial.sh"
}
test_changed_hotplug_layout_does_not_partially_write_init() {
    cp "$TEST_TMP/official-init" "$init"
    cp "$TEST_TMP/official-hotplug" "$hotplug"
    rewrite "$hotplug" '[ -n "$slot_type" ] || exit' '[ -n "$slot_type" ] || exit 1'
    cp "$hotplug" "$TEST_TMP/before-hotplug"
    reject sh "$patch" "$feed"
    assert_same "$init" "$TEST_TMP/official-init"
    assert_same "$hotplug" "$TEST_TMP/before-hotplug"
}
run_tests "$@"
