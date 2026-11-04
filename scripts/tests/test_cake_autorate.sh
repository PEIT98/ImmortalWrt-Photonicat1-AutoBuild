#!/bin/bash
source "$(dirname "$0")/common.sh"
setup() {
    state="$TEST_TMP/state.json"; cp "$ROOT/scripts/tests/fixtures/cake-state.json" "$state"
    bin="$TEST_TMP/bin"; mkdir "$bin"
    cp "$ROOT/scripts/tests/fixtures/mock-cake.sh" "$TEST_TMP/mock"; chmod +x "$TEST_TMP/mock"
    for name in uci ubus tc jsonfilter cake-service; do ln -s "$TEST_TMP/mock" "$bin/$name"; done
    export PATH="$bin:$PATH" CAKE_TEST_STATE="$state" CAKE_TEST_CALLS="$TEST_TMP/calls" CAKE_AUTORATE_CONFIG_DIR="$TEST_TMP/runtime"
    prepare="$ROOT/packages/cake-autorate/files/cake-autorate-prepare"
}
test_check_readonly() {
    ok sh "$prepare" check; assert_has "$OUT" 6_2; assert_has "$OUT" ifb-real2
    assert_absent "$TEST_TMP/runtime"
}
test_generate_configuration() {
    ok sh "$prepare" config
    local config; config=$(cat "$OUT")
    assert_eq 600 "$(stat -c %a "$config")"; ok bash -n "$config"
    for value in 'dl_if="ifb-real2"' 'ul_if="wwan0_2"' 'mwan3 use 6_2 exec' '-4 -I wwan0_2' log_to_file=0; do assert_has "$config" "$value"; done
}
test_rejection_matrix() {
    while IFS=$'\t' read -r expr message; do
        cp "$ROOT/scripts/tests/fixtures/cake-state.json" "$state"; update_json "$state" "$expr"
        reject sh "$prepare" config; assert_has "$ERR" "$message"; assert_absent "$TEST_TMP/runtime/config.primary.sh"
    done <<'CASES'
del(.uci["mwan3.qmodem_priority3.interface"])	尚未发现
.uci["qmodem.modem2"]="other"	不是有效的 QModem
.status.up=false	未连接
.uci["mwan3.6_2.family"]="ipv6"	IPv4
.uci["firewall.@defaults[0].flow_offloading_hw"]="1"	流量分载
.queues=[]	唯一的 CAKE
.queues+=["duplicate"]|.uci+={"sqm.duplicate.enabled":"1","sqm.duplicate.interface":"wwan0_2","sqm.duplicate.qdisc":"cake"}	唯一的 CAKE
.uci["sqm.mobile.qdisc"]="fq_codel"	未使用 CAKE
.cake_devices-=["wwan0_2"]	上传 CAKE
.cake_devices-=["ifb-real2"]	下载 CAKE
.filters=[]	唯一的下载 IFB
.filters[0].options.actions+=[{to_dev:"ifb-other"}]	唯一的下载 IFB
.uci["cake-autorate.main.base_download"]="0"	实测速率
.uci["cake-autorate.main.min_download"]="300000"	最低 <= 基准 <= 最高
.uci["cake-autorate.main.base_download"]="$(touch bad)"	正整数
.uci["cake-autorate.main.base_download"]="080000"	正整数
.uci["cake-autorate.main.reflector"]="223.5.5.5 999.1.1.1"	IPv4 地址
.status.l3_device="wwan1"	唯一的 CAKE
CASES
}
integration() {
    mkdir -p "$TEST_TMP/etc/config" "$TEST_TMP/rom/etc/config"
    for relative in etc/config/travelmate etc/config/sqm rom/etc/config/sqm; do printf '# default configuration\n' > "$TEST_TMP/$relative"; done
    if [[ ${2:-} == custom ]]; then printf '# user sqm\n' > "$TEST_TMP/etc/config/sqm"; fi
    if [[ $1 == defaults ]]; then
        cp "$ROOT/files/etc/uci-defaults/92-photonicat-network-tools" "$TEST_TMP/integration.sh"
        export CAKE_TEST_WRITABLE=1
    else
        cp "$ROOT/packages/cake-autorate/files/98-cake-autorate" "$TEST_TMP/integration.sh"
        export CAKE_TEST_WRITABLE=0
    fi
    rewrite "$TEST_TMP/integration.sh" /rom/ @QA_ROM@
    rewrite "$TEST_TMP/integration.sh" /etc/config/ "$TEST_TMP/etc/config/"
    rewrite "$TEST_TMP/integration.sh" @QA_ROM@ "$TEST_TMP/rom/"
    rewrite "$TEST_TMP/integration.sh" /etc/init.d/cake-autorate "$bin/cake-service"
    rewrite "$TEST_TMP/integration.sh" /var/run/photonicat-cake-autorate/ "$TEST_TMP/runtime/"
    ok env ACTION=ifup INTERFACE=6_2 sh "$TEST_TMP/integration.sh"
    jq -s . "$TEST_TMP/calls" > "$TEST_TMP/calls.json"
}
test_first_boot_defaults() {
    integration defaults
    assert_json "$state" '.uci["network.wwan.proto"]=="dhcp" and .uci["travelmate.global.trm_iface"]=="wwan" and .uci["travelmate.global.trm_enabled"]=="0" and .uci["sqm.mobile.enabled"]=="0"'
}
test_preserve_existing_wwan() {
    update_json "$state" '.uci+={"network.wwan":"interface","network.wwan.proto":"static","network.wwan.metric":"55"}'
    integration defaults
    assert_json "$state" '.uci["network.wwan.proto"]=="static" and .uci["network.wwan.metric"]=="55"'
}
test_preserve_travelmate() {
    update_json "$state" '.uci+={"travelmate.global.trm_iface":"my_wifi","travelmate.global.trm_enabled":"1"}'
    integration defaults; assert_json "$state" '.uci["travelmate.global.trm_iface"]=="my_wifi" and .uci["travelmate.global.trm_enabled"]=="1"'
}
test_preserve_enabled_autorate() {
    update_json "$state" '.uci["cake-autorate.main.enabled"]="1"'; integration defaults
    assert_json "$TEST_TMP/calls.json" 'all(.[];.[0]!="cake-service")'
}
test_preserve_custom_sqm() {
    integration defaults custom; assert_json "$state" '.uci["sqm.mobile.enabled"]=="1"'
}
test_disabled_hotplug() {
    update_json "$state" '.uci["cake-autorate.main.enabled"]="0"'; integration hotplug
    assert_json "$TEST_TMP/calls.json" 'all(.[];.[0]!="cake-service")'
}
test_enabled_hotplug() {
    update_json "$state" '.uci["cake-autorate.main.enabled"]="1"'; integration hotplug
    assert_json "$TEST_TMP/calls.json" 'any(.[];.==["cake-service","restart"])'
}
test_unrelated_hotplug() {
    update_json "$state" '.uci["cake-autorate.main.enabled"]="1"|.uci["mwan3.qmodem_priority3.interface"]="other"|del(.uci["network.6_2.modem_config"])'; integration hotplug
    assert_json "$TEST_TMP/calls.json" 'all(.[];.[0]!="cake-service")'
}
run_tests "$@"
