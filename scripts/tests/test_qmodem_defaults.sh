#!/bin/bash
# 验证旧配置恢复、备份和重试；所有状态与服务均在临时目录中。
source "$(dirname "$0")/common.sh"
setup() {
    root="$TEST_TMP/root"; state="$TEST_TMP/state.json"
    mkdir -p "$root"/{bin,lib,etc/config,etc/rc.d,etc/init.d,usr/bin,etc/hotplug.d/iface,rom/etc/config}
    for package in qmodem network firewall dhcp mwan3; do printf '# saved %s\n' "$package" > "$root/etc/config/$package"; done
    touch "$root/etc/config/travelmate" "$root/etc/config/sqm" "$root/rom/etc/config/sqm"
    printf "config main 'main'\n" > "$root/rom/etc/config/qmodem"
    cat > "$state" <<'JSON'
{"uci":{"qmodem.main":"main","qmodem.main.enable_dial":"1","network.lan":"interface","network.lan.ipaddr":"172.16.0.1","network.wan":"interface","network.wan.metric":"5","firewall.wan":"zone","firewall.wan.name":"wan","firewall.wan.network":["wan"],"travelmate.global":"travelmate","sqm.example":"queue","sqm.example.enabled":"1"},"rom":{"qmodem.main":"main","qmodem.main.enable_usb_scan":"1","qmodem.main.enable_pcie_scan":"1","qmodem.main.try_preset_usb":"1","qmodem.main.try_preset_pcie":"1","qmodem.main.start_delay":"0","qmodem.main.scan_delay":"0"}}
JSON
    cp "$ROOT/scripts/tests/fixtures/mock-qmodem-defaults.sh" "$root/bin/uci"
    chmod +x "$root/bin/uci"
    cat > "$root/lib/functions.sh" <<'LIB'
config_load() { CONFIG_PACKAGE=$1; }
config_foreach() {
    local callback="$1" type="$2" section
    for section in $(jq -r --arg p "$CONFIG_PACKAGE" --arg t "$type" '.uci|to_entries[]|select((.key|startswith($p+".")) and (.key|split(".")|length)==2 and .value==$t)|.key|split(".")[1]' "$QMODEM_DEFAULTS_STATE"); do "$callback" "$section"; done
}
LIB
    service mwan3
    export QMODEM_DEFAULTS_STATE="$state" QMODEM_DEFAULTS_CALLS="$TEST_TMP/calls"
    export PHOTONICAT_DEFAULTS_ROOT="$root" PATH="$root/bin:$PATH"
    defaults="$ROOT/files/etc/uci-defaults/99-photonicat-network"
}
service() {
    printf '#!/bin/sh\nprintf "%%s %%s\\n" "${0##*/}" "$*" >> "$PHOTONICAT_DEFAULTS_ROOT/service-calls"\n[ ! -f "$PHOTONICAT_DEFAULTS_ROOT/fail-${0##*/}" ]\n' > "$root/etc/init.d/$1"
    chmod +x "$root/etc/init.d/$1"
}
apply_defaults() { ok sh "$defaults"; }
modem() {
    update_json "$state" '.uci+={"qmodem.main.photonicat_fixed_5g_v1":"1","qmodem.main.enable_usb_scan":"1","qmodem.main.enable_pcie_scan":"0","qmodem.main.try_preset_usb":"0","qmodem.main.try_preset_pcie":"0","qmodem.main.scan_delay":"15","qmodem.6_2":"modem-device","qmodem.6_2.alias":"wwan_5g","qmodem.6_2.data_interface":"usb","qmodem.6_2.path":"/sys/bus/usb/devices/6-2/","qmodem.6_2.apn":"custom-apn","qmodem.6_2.at_port":"/dev/ttyUSB4","qmodem.6_2.driver":"rndis","qmodem.6_2.pdp_index":"3","qmodem.6_2.metric":"30","qmodem.6_2.host_ipv4_owner":"netifd","qmodem.slot":"modem-slot","qmodem.slot.slot":"6-2","qmodem.slot.type":"usb","qmodem.slot.alias":"wwan_5g","qmodem.slot.default_metric":"30","mwan3.qmodem_priority3":"member","mwan3.qmodem_priority3.interface":"wwan_5g","network.wwan_5g":"interface","network.wwan_5g.modem_config":"6_2","network.wwan_5g.proto":"qmodem_runtime","network.wwan_5gv6":"interface","network.wwan_5gv6.modem_config":"6_2","dhcp.wwan_5gv6":"dhcp","dhcp.wwan_5gv6.interface":"wwan_5gv6","dhcp.lan.ra":"relay"}|.uci["firewall.wan.network"]+=["wwan_5g","wwan_5gv6"]'
}
snapshot_qmodem() { jq -S '.uci|with_entries(select(.key|startswith("qmodem.")))' "$state" > "$1"; }
test_fresh_install_leaves_qmodem_defaults_untouched() {
    snapshot_qmodem "$TEST_TMP/before"
    apply_defaults
    snapshot_qmodem "$TEST_TMP/after"; assert_same "$TEST_TMP/before" "$TEST_TMP/after"
    assert_json "$state" '.uci["network.lan.ipaddr"]=="172.16.0.1" and (.uci|has("network.wan.metric")|not) and .uci["network.wwan.proto"]=="dhcp" and (.uci|has("network.wwan.metric")|not)'
    assert_json "$state" '.uci["firewall.wan.network"]==["wan","wwan"] and .uci["travelmate.global.trm_enabled"]=="0" and .uci["sqm.example.enabled"]=="0"'
    assert_has "$root/service-calls" 'mwan3 disable'; assert_has "$root/service-calls" 'mwan3 stop'
    assert_absent "$root/root"
}
test_old_customizations_restore_without_losing_apn_or_ports() {
    modem; apply_defaults
    assert_json "$state" '.uci as $u | .rom|to_entries|all(.[]; $u[.key]==.value)'
    assert_json "$state" '.uci["qmodem.6_2.apn"]=="custom-apn" and .uci["qmodem.6_2.at_port"]=="/dev/ttyUSB4" and .uci["qmodem.6_2.driver"]=="rndis" and .uci["qmodem.6_2.pdp_index"]=="3"'
    for key in qmodem.6_2.alias qmodem.6_2.metric qmodem.6_2.host_ipv4_owner qmodem.slot qmodem.main.photonicat_fixed_5g_v1 network.wwan_5g network.wwan_5gv6 dhcp.wwan_5gv6; do
        assert_json "$state" ".uci|has(\"$key\")|not"
    done
    assert_json "$state" '.uci["firewall.wan.network"]==["wan","wwan"] and .uci["dhcp.lan.ra"]=="relay"'
    backup=$(find "$root/root" -mindepth 1 -maxdepth 1 -type d)
    assert_eq 700 "$(stat -c %a "$backup")"
    for package in qmodem network firewall dhcp mwan3; do assert_same "$root/etc/config/$package" "$backup/$package"; done
}
test_reads_defaults_from_new_image_instead_of_hardcoding_values() {
    modem; update_json "$state" '.rom["qmodem.main.scan_delay"]="23"|del(.rom["qmodem.main.try_preset_usb"])'
    apply_defaults
    assert_json "$state" '.uci["qmodem.main.scan_delay"]=="23" and (.uci|has("qmodem.main.try_preset_usb")|not)'
}
test_foreign_fixed_interface_and_custom_slot_options_are_preserved() {
    modem
    update_json "$state" '.uci+={"qmodem.slot.gpio":"modem-power","qmodem.6_2.metric":"55","network.wwan_5g.modem_config":"another","network.wwan_5gv6.modem_config":"another","dhcp.wwan_5gv6.interface":"custom"}'
    apply_defaults
    assert_json "$state" '.uci["qmodem.slot"]=="modem-slot" and .uci["qmodem.slot.gpio"]=="modem-power" and (.uci|has("qmodem.slot.alias")|not) and (.uci|has("qmodem.slot.default_metric")|not) and .uci["qmodem.6_2.metric"]=="55"'
    assert_json "$state" '.uci["network.wwan_5g.modem_config"]=="another" and .uci["dhcp.wwan_5gv6.interface"]=="custom" and (.uci["firewall.wan.network"]|index("wwan_5g")!=null)'
}
test_custom_alias_owner_and_routes_are_preserved() {
    modem
    update_json "$state" '.uci+={"qmodem.6_2.alias":"mobile_custom","qmodem.6_2.host_ipv4_owner":"legacy","qmodem.slot.alias":"custom_slot","network.wan.metric":"17","network.wwan":"interface","network.wwan.metric":"25","network.wwan.proto":"static"}'
    apply_defaults
    assert_json "$state" '.uci["qmodem.6_2.alias"]=="mobile_custom" and .uci["qmodem.6_2.host_ipv4_owner"]=="legacy" and .uci["qmodem.slot.alias"]=="custom_slot" and .uci["network.wan.metric"]=="17" and .uci["network.wwan.metric"]=="25" and .uci["network.wwan.proto"]=="static"'
}
test_completed_restore_preserves_later_user_changes() {
    modem; apply_defaults
    update_json "$state" '.uci+={"qmodem.main.enable_usb_scan":"0","qmodem.6_2.alias":"later_alias","network.wan.metric":"5"}'
    cp "$state" "$TEST_TMP/before"; cp "$root/service-calls" "$TEST_TMP/services"
    apply_defaults
    assert_same "$state" "$TEST_TMP/before"; assert_same "$root/service-calls" "$TEST_TMP/services"
}
test_missing_rom_retries_without_marking_restore_complete() {
    modem; mv "$root/rom/etc/config/qmodem" "$root/rom/saved"
    snapshot_qmodem "$TEST_TMP/before"
    reject sh "$defaults"; assert_has "$ERR" '缺少官方 QModem 默认配置'
    snapshot_qmodem "$TEST_TMP/after"; assert_same "$TEST_TMP/before" "$TEST_TMP/after"
    assert_json "$state" '(.uci|has("network.globals.photonicat_stock_network_v1")|not) and .uci["network.globals.photonicat_tools_v1"]=="1"'
    mv "$root/rom/saved" "$root/rom/etc/config/qmodem"; apply_defaults
    assert_json "$state" '.uci["network.globals.photonicat_stock_network_v1"]=="1"'
}
test_invalid_rom_does_not_change_qmodem() {
    modem; update_json "$state" '.rom["qmodem.main"]="invalid"'
    snapshot_qmodem "$TEST_TMP/before"
    reject sh "$defaults"; assert_has "$ERR" '官方 QModem 默认配置无效'
    snapshot_qmodem "$TEST_TMP/after"; assert_same "$TEST_TMP/before" "$TEST_TMP/after"
}
test_marker_commit_failure_is_reverted_and_retried() {
    modem; update_json "$state" '.fail_commit_when="network.globals.photonicat_stock_network_v1"'
    reject sh "$defaults"
    assert_json "$state" '(.uci|has("network.globals.photonicat_stock_network_v1")|not)'
    update_json "$state" 'del(.fail_commit_when)'
    apply_defaults
    assert_json "$state" '.uci["network.globals.photonicat_stock_network_v1"]=="1" and .uci["qmodem.6_2.apn"]=="custom-apn"'
}
test_sourced_defaults_work_with_unset_system_variables() {
    printf '%s\n' '[ -z "$IPKG_INSTROOT" ] || true' > "$TEST_TMP/functions"
    cat "$root/lib/functions.sh" >> "$TEST_TMP/functions"
    cp "$TEST_TMP/functions" "$root/lib/functions.sh"
    modem
    ok env -u IPKG_INSTROOT sh -uc '( . "$1" )' sh "$defaults"
    assert_json "$state" '.uci["network.globals.photonicat_stock_network_v1"]=="1"'
}
test_old_background_services_and_hooks_are_removed() {
    for name in photonicat-qmodem-mwan3 photonicat-qmodem-scan; do
        service "$name"; ln -s "../init.d/$name" "$root/etc/rc.d/S99$name"
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
test_mwan3_failure_leaves_restore_pending() {
    touch "$root/fail-mwan3"
    reject sh "$defaults"; assert_has "$ERR" '无法关闭 mwan3 默认启动'
    assert_json "$state" '(.uci|has("network.globals.photonicat_stock_network_v1")|not)'
    rm "$root/fail-mwan3"; apply_defaults
    assert_json "$state" '.uci["network.globals.photonicat_stock_network_v1"]=="1"'
}
test_missing_firewall_retries_independently() {
    update_json "$state" 'del(.uci["firewall.wan"],.uci["firewall.wan.name"])'
    reject sh "$defaults"
    assert_json "$state" '.uci["network.globals.photonicat_stock_network_v1"]=="1" and (.uci|has("network.globals.photonicat_wan_v1")|not)'
    update_json "$state" '.uci+={"firewall.wan":"zone","firewall.wan.name":"wan"}'
    apply_defaults
}
test_image_uses_official_runtime_and_driver_defaults() {
    assert_absent "$ROOT/files/etc/config/mwan3"
    assert_absent "$ROOT/scripts/patches/fix-qmodem-netifd-owner.sh"
    assert_not_has "$ROOT/.github/workflows/build.yml" 'fix-qmodem-netifd-owner'
    assert_not_has "$ROOT/files/etc/config/network" "option metric"
    assert_has "$ROOT/photonicat1.config" 'CONFIG_PACKAGE_qmodem_INCLUDE_vendor-qmi-wwan=y'
    for path in etc/config/qmodem usr/share/qmodem lib/netifd/proto/qmodem_runtime.sh; do assert_absent "$ROOT/files/$path"; done
}
test_runtime_check_rejects_changes_to_official_dialing_source() {
    feed="$TEST_TMP/build/feeds/qmodem"
    mkdir -p "$feed/application/qmodem"; printf '# official\n' > "$feed/application/qmodem/dial"
    git -C "$feed" init -q; git -C "$feed" add .
    git -C "$feed" -c user.name=Test -c user.email=test@example.invalid commit -qm fixture
    ok bash "$ROOT/scripts/build/verify-qmodem-feeds.sh" runtime "$TEST_TMP/build"
    printf '# modified\n' >> "$feed/application/qmodem/dial"
    reject bash "$ROOT/scripts/build/verify-qmodem-feeds.sh" runtime "$TEST_TMP/build"
}
run_tests "$@"
