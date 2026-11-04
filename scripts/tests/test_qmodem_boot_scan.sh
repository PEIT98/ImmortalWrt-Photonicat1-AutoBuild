#!/bin/bash
source "$(dirname "$0")/common.sh"
setup() {
    export GUARD_TEST_ROOT="$TEST_TMP/root"
    root=$GUARD_TEST_ROOT
    mkdir -p "$root"/{bin,dev,run,sys/class/net,sys/class/tty}
    for cmd in uci modem_scanc qmodem_init guard_init logger; do cp "$ROOT/scripts/tests/fixtures/mock-boot-scan.sh" "$root/bin/$cmd"; chmod +x "$root/bin/$cmd"; done
    state="$root/state.json"; printf '{}\n' > "$state"
    export PATH="$root/bin:$PATH"
    export PHOTONICAT_QMODEM_SYSFS="$root/sys" PHOTONICAT_QMODEM_DEVFS="$root/dev" PHOTONICAT_QMODEM_RUNDIR="$root/run"
    export PHOTONICAT_QMODEM_SCANC="$root/bin/modem_scanc" PHOTONICAT_QMODEM_INIT="$root/bin/qmodem_init" PHOTONICAT_QMODEM_GUARD_INIT="$root/bin/guard_init"
    export PHOTONICAT_QMODEM_INTERVAL=0 PHOTONICAT_QMODEM_ROUNDS=8 PHOTONICAT_QMODEM_RECOVERY_ROUND=4
    helper="$ROOT/files/usr/bin/photonicat-qmodem-scan"
    defaults="$ROOT/files/etc/uci-defaults/zz-photonicat-qmodem-usb-scan"
    read -r -a test_shell <<<"${TEST_SH:-sh}"
}
hardware() {
    local tty=${1:-1} kind=${2:-normal}
    local device="$root/sys/devices/usb6/6-2"
    mkdir -p "$device/6-2:1.2" "$device/6-2:1.4" "$root/sys/bus/usb/drivers/cdc_ether" "$root/sys/class/net/enx_dynamic" "$root/sys/class/tty/ttyUSB2"
    printf '2cb7\n' > "$device/idVendor"; printf '0105\n' > "$device/idProduct"
    ln -s "$root/sys/bus/usb/drivers/cdc_ether" "$device/6-2:1.4/driver"
    ln -s "$device/6-2:1.4" "$root/sys/class/net/enx_dynamic/device"
    ln -s "$device/6-2:1.2" "$root/sys/class/tty/ttyUSB2/device"
    if [[ $tty == 1 ]]; then ln -s /dev/null "$root/dev/ttyUSB2"; fi
    local at=/dev/ttyUSB2
    if [[ $kind == wrong ]]; then at=/dev/ttyUSB9; update_json "$state" '.wrong_at=true'; fi
    cat > "$root/device.conf" <<CONFIG
qmodem.custom_alias=modem-device
qmodem.custom_alias.path='$device/'
qmodem.custom_alias.data_interface='usb'
qmodem.custom_alias.state='enabled'
qmodem.custom_alias.name='fm160-eau'
qmodem.custom_alias.network='enx_dynamic'
qmodem.custom_alias.at_port='$at'
CONFIG
    if [[ $kind == fixed ]]; then printf "qmodem.custom_alias.fixed_device='1'\n" >> "$root/device.conf"; update_json "$state" '.fixed=true'; fi
}
run_helper() { ok timeout 20 "${test_shell[@]}" "${1:-$helper}"; if [[ ! -e $root/events.jsonl ]]; then touch "$root/events.jsonl"; fi; jq -s . "$root/events.jsonl" > "$root/events.json"; }
no_recovery() { assert_json "$root/events.json" '[.[]|select(.[0]=="init")]|length==0'; }
no_actions() { assert_json "$root/events.json" '[.[]|select(.[0]=="init" or .[0]=="scan")]|length==0'; }
test_late_tty() {
    hardware 0; update_json "$state" '.tty_after=3|.mode="immediate"'
    run_helper; assert_json "$root/events.json" '[.[]|select(.[0]=="scan")]==[["scan",3,["add","6-2","usb"]]]'
    assert_json "$state" '.configured'; no_recovery
}
test_queued_task() {
    hardware; update_json "$state" '.mode="queued"|.complete_after=6'; export PHOTONICAT_QMODEM_RECOVERY_ROUND=7
    run_helper; assert_json "$root/events.json" '[.[]|select(.[0]=="scan")]|length==1'; assert_json "$state" '.configured'; no_recovery
}
test_busy_scan() {
    hardware; update_json "$state" '.mode="immediate"|.busy_until=3'; export PHOTONICAT_QMODEM_RECOVERY_ROUND=7
    run_helper; assert_json "$root/events.json" '[.[]|select(.[0]=="scan")]==[["scan",4,["add","6-2","usb"]]]'; no_recovery
}
test_stalled_recovery() {
    hardware; update_json "$state" '.mode="recover"'; run_helper
    assert_json "$root/events.json" '[.[]|select(.[0]=="init")|.[2]]==[["restart"]]'; assert_json "$state" '.configured'
}
test_recovery_boundary() {
    hardware; update_json "$state" '.mode="queued"|.complete_after=5'; run_helper
    assert_json "$state" '.configured'; no_recovery
}
test_recovery_only_once() {
    hardware; run_helper
    assert_json "$root/events.json" '[.[]|select(.[0]=="init")]|length==1'; assert_json "$state" '.tick<=9'
}
test_known_modem() { hardware; update_json "$state" '.configured=true'; run_helper; no_actions; }
test_fixed_device() { hardware 1 fixed; run_helper; no_actions; }
test_other_modem_prevents_recovery() {
    hardware; mkdir "$root/sys/class/net/wan_modem"; update_json "$state" '.active_other=true'; run_helper
    assert_json "$root/events.json" '[.[]|select(.[0]=="scan")]|length>0'; no_recovery
}
test_no_modem() { run_helper; no_actions; }
test_wrong_at_port() {
    hardware 1 wrong; run_helper
    assert_json "$root/events.json" '[.[]|select(.[0]=="scan")]|length>0'; no_recovery
}
test_disabled_scanning() {
    for expr in '.enabled="0"' '.blocked="1"'; do
        printf '{}\n' > "$state"; update_json "$state" "$expr"; run_helper; no_actions
    done
}
test_guard_lock() {
    hardware; exec 8>"$root/run/photonicat-qmodem-scan.lock"; flock 8
    run_helper; no_actions
}
test_hung_uci_bounded() {
    update_json "$state" '.hang_uci=true'; export PHOTONICAT_QMODEM_ROUNDS=1
    run_helper; no_actions
}
test_upgrade_preserves_settings() {
    printf '{"values":{"qmodem.main":"main","qmodem.main.photonicat_usb_scan_defaults":"1","qmodem.main.enable_usb_scan":"0","qmodem.main.enable_pcie_scan":"1","qmodem.main.start_delay":"30"}}\n' > "$state"
    cp "$state" "$TEST_TMP/before"
    run_helper "$defaults"
    for key in qmodem.main.enable_usb_scan qmodem.main.enable_pcie_scan qmodem.main.start_delay; do assert_eq "$(jq -r --arg key "$key" '.values[$key]' "$TEST_TMP/before")" "$(jq -r --arg key "$key" '.values[$key]' "$state")"; done
    assert_json "$root/events.json" '[.[]|select(.[0]=="enable")]|length==1'
    run_helper "$defaults"; assert_json "$root/events.json" '[.[]|select(.[0]=="enable")]|length==1'
}
test_fresh_usb_defaults() {
    printf '{"values":{"qmodem.main":"main"}}\n' > "$state"; run_helper "$defaults"
    assert_json "$state" '.values["qmodem.main.enable_usb_scan"]=="1" and .values["qmodem.main.enable_pcie_scan"]=="0" and .values["qmodem.main.try_preset_pcie"]=="0"'
}
# Real patched boot function, replacing only its external scan client.
boot_source() {
    mkdir -p "$root/feed/application/qmodem/files/etc/init.d"
    cat > "$root/feed/application/qmodem/files/etc/init.d/qmodem_init" <<'BOOT'
boot() {
    local delay=$(uci -q get qmodem.main.start_delay || echo 0)
    if [ "$delay" -gt 0 ]; then
        logger "Delay QModem Boot init scan for $delay S"
        ( sleep "$delay"; /usr/share/qmodem/modem_scan.sh scan >/dev/null 2>&1 ) &
    fi
    start
}
other() { echo unchanged; }
BOOT
    boot="$root/feed/application/qmodem/files/etc/init.d/qmodem_init"
    ok sh "$ROOT/scripts/patches/fix-qmodem-boot-scan.sh" "$root/feed"
}
test_boot_switch_combinations() {
    boot_source
    cp "$boot" "$TEST_TMP/boot.sh"
    rewrite "$TEST_TMP/boot.sh" /usr/share/qmodem/modem_scan.sh '"$SCAN_CLIENT"'
    printf '\nlogger() { :; }\nsleep() { :; }\nstart() { echo started; }\nboot\nwait\n' >> "$TEST_TMP/boot.sh"
    printf '#!/bin/sh\ncase "$3" in\nqmodem.main.start_delay) echo "$SCAN_DELAY";;\nqmodem.main.enable_usb_scan) echo "$USB_SCAN";;\nqmodem.main.enable_pcie_scan) echo "$PCIE_SCAN";;\n*) exit 1;;\nesac\n' > "$root/bin/uci"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$SCAN_EVENTS"\n' > "$root/bin/scan"
    chmod +x "$root/bin/scan"
    export SCAN_CLIENT="$root/bin/scan" SCAN_EVENTS="$root/scans" SCAN_DELAY=15
    for pair in '1 0 usb' '0 1 pcie' '1 1 all' '0 0 none'; do
        read -r USB_SCAN PCIE_SCAN expected <<< "$pair"; export USB_SCAN PCIE_SCAN
        rm -f "$SCAN_EVENTS"; ok "${test_shell[@]}" "$TEST_TMP/boot.sh"; assert_eq started "$(cat "$OUT")"
        if [[ $expected == none ]]; then assert_absent "$SCAN_EVENTS"; else assert_eq "scan $expected" "$(cat "$SCAN_EVENTS")"; fi
    done
    export USB_SCAN=1 PCIE_SCAN=1 SCAN_DELAY=0
    rm -f "$SCAN_EVENTS"; ok "${test_shell[@]}" "$TEST_TMP/boot.sh"; assert_absent "$SCAN_EVENTS"
}
test_boot_patch_repeated_and_scope() {
    boot_source; cp "$boot" "$TEST_TMP/once"
    ok sh "$ROOT/scripts/patches/fix-qmodem-boot-scan.sh" "$root/feed"
    assert_same "$boot" "$TEST_TMP/once"; assert_has "$boot" 'other() { echo unchanged; }'
}
test_boot_upstream_drift() {
    boot_source; printf 'boot() { changed_upstream; }\n' > "$boot"
    reject sh "$ROOT/scripts/patches/fix-qmodem-boot-scan.sh" "$root/feed"
}
run_tests "$@"
