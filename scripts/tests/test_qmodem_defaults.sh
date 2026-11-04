#!/bin/bash
source "$(dirname "$0")/common.sh"
FEED=${1:-}
setup() {
    root="$TEST_TMP/root"; state="$TEST_TMP/state.json"
    mkdir -p "$root"/{bin,lib,etc/config,etc/rc.d,etc/init.d,usr/bin,etc/hotplug.d/iface}
    touch "$root/etc/config/mwan3"
    printf '%s\n' '{"uci":{"qmodem.main":"main","qmodem.main.enable_dial":"1","network.lan":"interface","network.lan.ipaddr":"172.16.0.1","mwan3.failover":"policy","mwan3.failover.use_member":["wan_priority1","wwan_priority2"],"firewall.wan":"zone","firewall.wan.name":"wan","firewall.wan.network":["wan","wwan"]}}' > "$state"
    cp "$ROOT/scripts/tests/fixtures/mock-qmodem-defaults.sh" "$root/bin/uci"
    chmod +x "$root/bin/uci"
    cat > "$root/lib/functions.sh" <<'LIB'
config_load() { CONFIG_PACKAGE=$1; }
config_foreach() {
    local callback="$1" type="$2" section
    for section in $(jq -r --arg p "$CONFIG_PACKAGE" --arg t "$type" '.uci|to_entries[]|select((.key|startswith($p+".")) and (.key|split(".")|length)==2 and .value==$t)|.key|split(".")[1]' "$QMODEM_DEFAULTS_STATE"); do "$callback" "$section"; done
}
config_get() {
    local value
    value=$(uci -q get "$CONFIG_PACKAGE.$2.$3" 2>/dev/null) || value=${4:-}
    export "$1=$value"
}
LIB
    export QMODEM_DEFAULTS_STATE="$state" QMODEM_DEFAULTS_CALLS="$TEST_TMP/calls"
    export PHOTONICAT_DEFAULTS_ROOT="$root" IPKG_INSTROOT="$root" PATH="$root/bin:$PATH"
    defaults="$ROOT/files/etc/uci-defaults/99-photonicat-qmodem"
}
apply_defaults() { ok sh "$defaults"; }
modem() {
    update_json "$state" '.uci+={"qmodem.6_2":"modem-device","qmodem.6_2.data_interface":"usb","qmodem.6_2.path":"/sys/bus/usb/devices/6-2/","qmodem.6_2.apn":"custom-apn","qmodem.6_2.at_port":"/dev/ttyUSB4","qmodem.6_2.metric":"11"}'
}
test_fresh_fixed_alias_and_single_scan_settings() {
    apply_defaults
    assert_json "$state" '.uci["qmodem.cfg001"]=="modem-slot" and .uci["qmodem.cfg001.slot"]=="6-1" and .uci["qmodem.cfg001.alias"]=="wwan_5g" and .uci["qmodem.cfg001.default_metric"]=="30"'
    assert_json "$state" '.uci["mwan3.qmodem_priority3.interface"]=="wwan_5g" and .uci["mwan3.qmodem_priority3.metric"]=="3" and .uci["mwan3.wwan_5g.family"]=="ipv4" and (.uci["mwan3.failover.use_member"]|index("qmodem_priority3")!=null)'
    assert_json "$state" '.uci["qmodem.main.enable_usb_scan"]=="1" and .uci["qmodem.main.enable_pcie_scan"]=="0" and .uci["qmodem.main.try_preset_usb"]=="0" and .uci["qmodem.main.try_preset_pcie"]=="0" and .uci["qmodem.main.start_delay"]=="0" and .uci["qmodem.main.scan_delay"]=="15"'
    assert_json "$state" '(.uci|has("network.wwan_5g")|not) and .uci["network.lan.ipaddr"]=="172.16.0.1"'
    jq -e '.uci["firewall.wan.network"]|contains(["wwan","wwan_5g","wwan_5gv6"])' "$state" >/dev/null
}
test_existing_modem_migrates_without_touching_apn() {
    modem
    update_json "$state" '.uci+={"mwan3.qmodem_priority3":"member","mwan3.qmodem_priority3.interface":"6_2","mwan3.6_2":"interface","network.6_2":"interface","network.6_2.modem_config":"6_2","network.6_2.proto":"qmodem_runtime","network.6_2v6":"interface","network.6_2v6.modem_config":"6_2","network.6_2v6.device":"@6_2","network.6_2v6.ifname":"@6_2"}|.uci["firewall.wan.network"]+=["6_2","6_2v6"]'
    apply_defaults
    assert_json "$state" '.uci["qmodem.6_2.alias"]=="wwan_5g" and .uci["qmodem.6_2.metric"]=="30" and .uci["qmodem.6_2.apn"]=="custom-apn" and .uci["qmodem.6_2.at_port"]=="/dev/ttyUSB4"'
    assert_json "$state" '.uci["qmodem.cfg001.slot"]=="6-2" and .uci["network.wwan_5g.modem_config"]=="6_2" and .uci["network.wwan_5g.proto"]=="qmodem_runtime" and .uci["network.wwan_5gv6.device"]=="@wwan_5g" and .uci["network.wwan_5gv6.ifname"]=="@wwan_5g"'
    assert_json "$state" '(.uci|has("network.6_2")|not) and (.uci|has("mwan3.6_2")|not) and (.uci["firewall.wan.network"]|index("6_2")==null)'
}
test_existing_slot_is_reused() {
    modem
    update_json "$state" '.uci+={"qmodem.saved_slot":"modem-slot","qmodem.saved_slot.slot":"6-2","qmodem.saved_slot.type":"usb","qmodem.saved_slot.alias":"old","qmodem.saved_slot.default_metric":"11"}'
    apply_defaults
    assert_json "$state" '.uci["qmodem.saved_slot.alias"]=="wwan_5g" and .uci["qmodem.saved_slot.default_metric"]=="30" and (.uci|has("qmodem.cfg001")|not)'
}
test_ipv6_relay_follows_renamed_interface() {
    modem
    update_json "$state" '.uci+={"network.6_2v6":"interface","network.6_2v6.modem_config":"6_2","network.6_2v6.device":"@6_2","dhcp.6_2v6":"dhcp","dhcp.6_2v6.interface":"6_2v6","dhcp.6_2v6.ra":"relay","dhcp.6_2v6.master":"1","dhcp.lan":"dhcp","dhcp.lan.ra":"relay"}'
    apply_defaults
    assert_json "$state" '.uci["dhcp.wwan_5gv6.interface"]=="wwan_5gv6" and .uci["dhcp.wwan_5gv6.ra"]=="relay" and .uci["dhcp.wwan_5gv6.master"]=="1" and .uci["dhcp.lan.ra"]=="relay" and (.uci|has("dhcp.6_2v6")|not)'
}
test_unrelated_policy_and_user_tracking_are_preserved() {
    update_json "$state" '.uci+={"mwan3.custom":"policy","mwan3.custom.last_resort":"unreachable","mwan3.failover.last_resort":"unreachable","mwan3.wwan_5g":"interface","mwan3.wwan_5g.family":"ipv6","mwan3.wwan_5g.track_ip":["9.9.9.9"],"mwan3.wwan_5g.interval":"17"}'
    apply_defaults
    assert_json "$state" '.uci["mwan3.custom.last_resort"]=="unreachable" and .uci["mwan3.failover.last_resort"]=="unreachable" and .uci["mwan3.wwan_5g.family"]=="ipv4" and .uci["mwan3.wwan_5g.track_ip"]==["9.9.9.9"] and .uci["mwan3.wwan_5g.interval"]=="17"'
}
test_fixed_dhcp_conflict_is_rejected_before_write() {
    update_json "$state" '.uci+={"dhcp.wwan_5gv6":"dhcp","dhcp.wwan_5gv6.interface":"other"}'
    cp "$state" "$TEST_TMP/before"; reject sh "$defaults"; assert_same "$state" "$TEST_TMP/before"
}
test_other_modem_and_disabled_dial_preserved() {
    modem
    update_json "$state" '.uci+={"mwan3.qmodem_priority3":"member","mwan3.qmodem_priority3.interface":"6_2","qmodem.other":"modem-device","qmodem.other.data_interface":"usb","qmodem.other.path":"/sys/bus/usb/devices/7-1/","qmodem.other.alias":"secondary","qmodem.other.apn":"other-apn","qmodem.6_2.enable_dial":"0","qmodem.main.enable_dial":"0"}'
    apply_defaults
    assert_json "$state" '.uci["qmodem.6_2.alias"]=="wwan_5g" and .uci["qmodem.other.alias"]=="secondary" and .uci["qmodem.other.apn"]=="other-apn" and .uci["qmodem.6_2.enable_dial"]=="0" and .uci["qmodem.main.enable_dial"]=="0"'
}
test_user_interface_conflict_is_rejected_before_write() {
    modem; update_json "$state" '.uci+={"network.wwan_5g":"interface","network.wwan_5g.proto":"dhcp"}'
    cp "$state" "$TEST_TMP/before"
    reject sh "$defaults"; assert_same "$state" "$TEST_TMP/before"
}
test_mwan_section_conflict_is_rejected() {
    update_json "$state" '.uci["mwan3.wwan_5g"]="rule"'; cp "$state" "$TEST_TMP/before"
    reject sh "$defaults"; assert_same "$state" "$TEST_TMP/before"
}
test_migration_runs_once_and_preserves_later_changes() {
    apply_defaults
    update_json "$state" '.uci["qmodem.main.enable_usb_scan"]="0"|.uci["qmodem.cfg001.alias"]="custom_later"'
    cp "$state" "$TEST_TMP/before"; apply_defaults; assert_same "$state" "$TEST_TMP/before"
}
test_commit_failure_does_not_mark_a_sourced_migration_complete() {
    update_json "$state" '.fail_commit=true'
    reject sh -c '( . "$1" ) && echo unexpected-success' sh "$defaults"
    assert_json "$state" '(.uci|has("qmodem.main.photonicat_fixed_5g_v1")|not)'
    assert_not_has "$OUT" unexpected-success
    assert_has "$ERR" 'UCI commit 失败'
}
test_old_services_and_hooks_are_removed() {
    for name in photonicat-qmodem-mwan3 photonicat-qmodem-scan; do
        printf '#!/bin/sh\nprintf "%%s %%s\\n" "${0##*/}" "$*" >> "$PHOTONICAT_DEFAULTS_ROOT/service-calls"\n' > "$root/etc/init.d/$name"
        chmod +x "$root/etc/init.d/$name"
        ln -s "../init.d/$name" "$root/etc/rc.d/S99$name"
    done
    touch "$root/etc/hotplug.d/iface/95-photonicat-qmodem-mwan3" "$root/usr/bin/photonicat-qmodem-mwan3-sync" "$root/usr/bin/photonicat-qmodem-scan"
    apply_defaults
    for name in photonicat-qmodem-mwan3 photonicat-qmodem-scan; do
        assert_absent "$root/etc/init.d/$name"; assert_absent "$root/etc/rc.d/S99$name"
        assert_has "$root/service-calls" "$name stop"; assert_has "$root/service-calls" "$name disable"
    done
    assert_absent "$root/usr/bin/photonicat-qmodem-mwan3-sync"
    assert_absent "$root/usr/bin/photonicat-qmodem-scan"
    assert_absent "$root/etc/hotplug.d/iface/95-photonicat-qmodem-mwan3"
}
test_official_boot_queues_exactly_one_usb_scan() {
    if [[ -z $FEED ]]; then fail 'provide QModem Feed directory for actual startup regression'; fi
    apply_defaults
    cp "$FEED/application/qmodem/files/etc/init.d/qmodem_init" "$TEST_TMP/init.sh"
    rewrite "$TEST_TMP/init.sh" /usr/bin/modem_scanc "$root/bin/modem_scanc"
    cat > "$root/bin/modem_scanc" <<'SCANC'
#!/bin/sh
if [ "$1" = status ]; then printf '{}\n'; else printf '%s\n' "$*" >> "$PHOTONICAT_DEFAULTS_ROOT/scans"; fi
SCANC
    chmod +x "$root/bin/modem_scanc"
    cat >> "$TEST_TMP/init.sh" <<'BOOT'
procd_open_instance() { :; }
procd_set_param() { :; }
procd_close_instance() { :; }
logger() { printf 'unexpected legacy delay\n' >> "$PHOTONICAT_DEFAULTS_ROOT/legacy-delay"; }
start() { start_service; }
boot
wait
BOOT
    ok timeout 8 sh "$TEST_TMP/init.sh"
    assert_eq 'scan usb 15' "$(cat "$root/scans")"
    assert_absent "$root/legacy-delay"
}
test_fixed_member_and_firewall_are_in_image_defaults() {
    awk '/^config member '\''qmodem_priority3'\''$/ {inside=1;next} /^config / {inside=0} inside && /option interface '\''wwan_5g'\''/ {found=1} END {exit !found}' "$ROOT/files/etc/config/mwan3"
    assert_has "$ROOT/files/etc/config/mwan3" "list use_member 'qmodem_priority3'"
    assert_has "$ROOT/files/etc/uci-defaults/90-photonicat-wan-firewall" 'for iface in wwan wwan_5g wwan_5gv6; do'
    assert_not_has "$ROOT/files/etc/config/network" "config interface 'wwan_5g'"
    for path in etc/init.d/photonicat-qmodem-scan etc/init.d/photonicat-qmodem-mwan3 usr/bin/photonicat-qmodem-scan usr/bin/photonicat-qmodem-mwan3-sync etc/hotplug.d/iface/95-photonicat-qmodem-mwan3; do assert_absent "$ROOT/files/$path"; done
}
run_tests "$@"
