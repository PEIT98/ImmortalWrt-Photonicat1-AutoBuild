#!/bin/bash
source "$(dirname "$0")/common.sh"
FEED=$(realpath "${1:?需要 QModem Feed 目录}")
DIAL=application/qmodem/files/usr/share/qmodem/modem_dial.sh
CM=application/quectel_CM_5G_M/src
setup() {
    feed="$TEST_TMP/feed"
    for path in "$DIAL" "$CM/QMIThread.h" "$CM/QMIThread.c" "$CM/udhcpc.c"; do mkdir -p "$(dirname "$feed/$path")"; cp "$FEED/$path" "$feed/$path"; done
    patch="$ROOT/scripts/patches/fix-qmodem-netifd-owner.sh"
}
test_repeated_and_atomic_rejection() {
    ok sh "$patch" "$feed"
    cp -a "$feed" "$TEST_TMP/once"
    ok sh "$patch" "$feed"
    diff -r "$feed" "$TEST_TMP/once"
    rewrite "$feed/$CM/QMIThread.c" '        profile->qmi_data_format_valid = 1; /* photonicat-qmi-format */
        profile->rawIP = (le32_to_cpu(linkProto->Value) == 2);' '/* changed upstream */'
    cp -a "$feed" "$TEST_TMP/drift"
    reject sh "$patch" "$feed"; assert_has "$ERR" '上游布局变化'
    diff -r "$feed" "$TEST_TMP/drift"
}
test_actual_format_and_events() {
    ok "${CC:-cc}" -ffunction-sections -fdata-sections -Wall -Wextra -Wno-unused-parameter "-DQMODEM_CM_SOURCE=\"$FEED/$CM/udhcpc.c\"" "$ROOT/scripts/tests/qmodem_qmi_format_harness.c" -Wl,--gc-sections -pthread -o "$TEST_TMP/format"
    ok "$TEST_TMP/format"
    ok "${CC:-cc}" -pthread "$FEED/application/quectel_CM_5G_M/tests/test_managed_ipv4.c" -o "$TEST_TMP/managed"
    ok "$TEST_TMP/managed"
}
test_real_ownership_conditions() {
    local sys="$TEST_TMP/sys"
    mkdir -p "$TEST_TMP/bin" "$sys/class/net/cell42/"{qmi,device} "$sys/bus/usb/drivers/qmi_wwan"
    cat > "$TEST_TMP/bin/uci" <<'UCI'
#!/bin/sh
for key do :; done
printf '%s\n' "$TEST_UCI" | jq -er --arg key "$key" '.[$key]//empty'
UCI
    chmod +x "$TEST_TMP/bin/uci"
    export PATH="$TEST_TMP/bin:$PATH"
    ln -s "$sys/bus/usb/drivers/qmi_wwan" "$sys/class/net/cell42/device/driver"
    raw="$sys/class/net/cell42/qmi/raw_ip"; printf 'N\n' > "$raw"
    caps=(usr/bin/quectel-CM-M usr/libexec/qmodem-ipv4-event lib/netifd/proto/qmodem_runtime.sh)
    for path in "${caps[@]}"; do mkdir -p "$(dirname "$TEST_TMP/$path")"; printf '#!/bin/sh\nexit 0\n' > "$TEST_TMP/$path"; chmod +x "$TEST_TMP/$path"; done
    awk 'BEGIN {RS="\0";ORS=""} {a=index($0,"# photonicat-netifd-owner:");b=index(substr($0,a),"dial(){");if(!a||!b)exit 1; print substr($0,a,b-1) > function_file;a=index($0,"    managed_ipv4=0\n");b=index(substr($0,a),"    m_debug \"modem_path=");if(!a||!b)exit 1; print substr($0,a,b-1)}' function_file="$TEST_TMP/function.sh" "$FEED/$DIAL" > "$TEST_TMP/decision.sh"
    rewrite "$TEST_TMP/decision.sh" /usr/bin/ "$TEST_TMP/usr/bin/"
    rewrite "$TEST_TMP/decision.sh" /usr/libexec/ "$TEST_TMP/usr/libexec/"
    cat "$TEST_TMP/function.sh" "$TEST_TMP/decision.sh" > "$TEST_TMP/combined.sh"
    cp "$TEST_TMP/combined.sh" "$TEST_TMP/decision.sh"
    printf '\nprintf "%%s" "$managed_ipv4"\n' >> "$TEST_TMP/decision.sh"
    export driver=qmi bridge_enabled=0 pdp_type=ipv4v6 modem_config=slot_dynamic modem_netcard=cell42
    export QMODEM_SYSFS_ROOT="$sys" PHOTONICAT_QMODEM_ROOT="$TEST_TMP"
    export TEST_UCI='{"qmodem.slot_dynamic.data_interface":"usb"}'
    owner() { ok env "$@" sh "$TEST_TMP/decision.sh"; cat "$OUT"; }
    assert_eq 1 "$(owner)"
    cp "$TEST_TMP/decision.sh" "$TEST_TMP/original.sh"
    rewrite "$TEST_TMP/original.sh" $'} ||\n                photonicat_netifd_owner; then' '}; then'
    ok sh "$TEST_TMP/original.sh"; assert_eq 0 "$(cat "$OUT")"
    for protocol in ecm mbim rndis ncm mhi; do assert_eq 0 "$(owner "driver=$protocol")"; done
    assert_eq 0 "$(owner bridge_enabled=1)"; assert_eq 0 "$(owner pdp_type=ipv6)"
    assert_eq 0 "$(owner 'TEST_UCI={"qmodem.slot_dynamic.data_interface":"pcie"}')"
    assert_eq 0 "$(owner 'TEST_UCI={"qmodem.slot_dynamic.data_interface":"usb","qmodem.slot_dynamic.host_ipv4_owner":"legacy"}')"
    assert_eq 1 "$(owner 'TEST_UCI={"qmodem.slot_dynamic.data_interface":"usb","qmodem.slot_dynamic.host_ipv4_owner":"netifd"}')"
    rm "$raw"; assert_eq 0 "$(owner)"; printf 'Y\n' > "$raw"
    rm "$sys/class/net/cell42/device/driver"; ln -s "$sys/bus/usb/drivers/qmi_wwan_q" "$sys/class/net/cell42/device/driver"
    assert_eq 0 "$(owner)"
    rm "$sys/class/net/cell42/device/driver"; ln -s "$sys/bus/usb/drivers/qmi_wwan" "$sys/class/net/cell42/device/driver"
    for path in "${caps[@]}"; do mv "$TEST_TMP/$path" "$TEST_TMP/$path.saved"; assert_eq 0 "$(owner)"; mv "$TEST_TMP/$path.saved" "$TEST_TMP/$path"; done
    printf '#!/bin/sh\nexit 0\n' > "$TEST_TMP/usr/libexec/qmodem-host-ipv4-owner"; chmod +x "$TEST_TMP/usr/libexec/qmodem-host-ipv4-owner"
    assert_eq 1 "$(owner driver=mbim)"
}
run_tests "$@"
