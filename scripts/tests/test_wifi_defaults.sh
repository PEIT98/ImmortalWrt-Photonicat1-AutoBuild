#!/bin/bash
# Run the generated mac80211.uc with native ucode and isolated board/UCI data.
source "$(dirname "$0")/common.sh"
WIFI_SOURCE_ROOT=${1:?需要 ImmortalWrt 源码目录}
UCODE=${UCODE:-$WIFI_SOURCE_ROOT/staging_dir/hostpkg/bin/ucode}
[[ -x $UCODE ]] || { echo "缺少主机 ucode：$UCODE" >&2; exit 1; }
setup() {
    wifi="$TEST_TMP/wifi"
    upstream="$WIFI_SOURCE_ROOT/package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
    mkdir -p "$wifi/package/network/config/wifi-scripts/files/lib/wifi"
    cp "$upstream" "$wifi/package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
    ok sh "$ROOT/scripts/patches/wifi-band-order.sh" "$wifi"
    generated="$wifi/files/lib/wifi/mac80211.uc"
    cat > "$TEST_TMP/run.uc" <<'UCODE'
function readfile(path) {
    if (path == "/etc/board.json")
        return sprintf("%J", test_board);
    return "02:00:00:00:00:01";
}
let uci = { cursor: () => ({ get_all: () => test_config }) };
UCODE
    # Only replace I/O imports; the complete production logic runs unchanged.
    sed '/^#!/d; /^import /d' "$generated" >> "$TEST_TMP/run.uc"
    fixture="$TEST_TMP/board.json"
    jq -n '{test_config:{},test_board:{wlan:{phy0:{path:"platform/pcie/pci0002:20/0002:21:00.0",info:{
        bands:{"2G":{default_channel:1,max_width:40,ht:true},
               "5G":{default_channel:36,max_width:160,he:true,vht:true}},radios:[]}}}}}' > "$fixture"
}
detect() { ok "$UCODE" -S -F "$fixture" "$TEST_TMP/run.uc"; }
assert_radios() { assert_eq "$1" "$(grep -c '=wifi-device$' "$OUT" || true)"; }
test_onboard_names_follow_sdio_bus_not_radio_index() {
    local path
    for path in platform/fe2c0000.mmc/mmc_host/mmc2/mmc2:0001/mmc2:0001:1 platform/fe2c0000.mmc/wifi platform/mmc_host/mmc2/wifi; do
        jq --arg path "$path" '.test_board.wlan.phy0.path=$path' "$fixture" > "$TEST_TMP/next"
        mv "$TEST_TMP/next" "$fixture"
        detect; assert_radios 1
        assert_has "$OUT" ".band='2g'"
        assert_has "$OUT" ".ssid='Pwrt'"
    done
}
test_single_radio_prefers_5g_and_uses_its_ssid() {
    detect; assert_radios 1
    assert_has "$OUT" ".band='5g'"
    assert_has "$OUT" ".ssid='Pwrt-5G'"
    assert_has "$OUT" ".htmode='HE80'"
    assert_has "$OUT" ".channel='36'"
    assert_has "$OUT" ".encryption='psk2'"
    assert_has "$OUT" ".key='photonicat'"
}
test_missing_or_disabled_5g_falls_back_to_2g() {
    cp "$fixture" "$TEST_TMP/original"
    local expr
    for expr in 'del(.test_board.wlan.phy0.info.bands["5G"])' 'del(.test_board.wlan.phy0.info.bands["5G"].default_channel)'; do
        jq "$expr" "$TEST_TMP/original" > "$fixture"
        detect; assert_radios 1
        assert_has "$OUT" ".band='2g'"
        assert_has "$OUT" ".ssid='Pwrt-2.4G'"
        assert_has "$OUT" ".htmode='HT20'"
    done
}
test_5g_only_card_and_driver_channel_are_preserved() {
    update_json "$fixture" 'del(.test_board.wlan.phy0.info.bands["2G"]) | .test_board.wlan.phy0.info.bands["5G"] |= (.default_channel=149 | .max_width=40 | del(.he))'
    detect; assert_radios 1
    assert_has "$OUT" ".ssid='Pwrt-5G'"
    assert_has "$OUT" ".channel='149'"
    assert_has "$OUT" ".htmode='VHT40'"
}
test_two_flexible_hardware_radios_get_different_bands() {
    update_json "$fixture" '.test_board.wlan.phy0.info.radios=[{index:0,bands:{"2G":{default_channel:1},"5G":{default_channel:36}}},{index:1,bands:{"2G":{default_channel:6},"5G":{default_channel:36}}}]'
    detect; assert_radios 2
    assert_eq 1 "$(grep -c "\.ssid='Pwrt-5G'" "$OUT")"
    assert_eq 1 "$(grep -c "\.ssid='Pwrt-2.4G'" "$OUT")"
    assert_has "$OUT" ".radio='0'"
    assert_has "$OUT" ".radio='1'"
}
test_band_assignment_reserves_the_only_5g_radio() {
    update_json "$fixture" '.test_board.wlan.phy0.info.radios=[{index:0,bands:{"2G":{default_channel:1},"5G":{default_channel:36}}},{index:1,bands:{"5G":{default_channel:36}}}]'
    detect; assert_radios 2
    assert_has "$OUT" "set wireless.radio0.band='2g'"
    assert_has "$OUT" "set wireless.radio1.band='5g'"
}
test_separate_phys_get_their_supported_bands() {
    update_json "$fixture" '.test_board.wlan.phy1=.test_board.wlan.phy0 | .test_board.wlan.phy1.path += "+1" | del(.test_board.wlan.phy0.info.bands["5G"],.test_board.wlan.phy1.info.bands["2G"])'
    detect; assert_radios 2
    assert_eq 1 "$(grep -c "\.ssid='Pwrt-5G'" "$OUT")"
    assert_eq 1 "$(grep -c "\.ssid='Pwrt-2.4G'" "$OUT")"
}
test_existing_user_wireless_configuration_is_not_regenerated() {
    update_json "$fixture" '.test_config={radio0:{".type":"wifi-device",path:.test_board.wlan.phy0.path,band:"2g"},default_radio0:{".type":"wifi-iface",ssid:"MyWireless"}}'
    detect; assert_radios 0
    assert_eq '' "$(cat "$OUT")"
}
test_disabled_bands_do_not_generate_invalid_ap() {
    update_json "$fixture" 'del(.test_board.wlan.phy0.info.bands["2G"].default_channel,.test_board.wlan.phy0.info.bands["5G"].default_channel)'
    detect; assert_radios 0
    assert_eq '' "$(cat "$OUT")"
}
test_patch_is_repeatable_and_rejects_upstream_drift() {
    cp "$generated" "$TEST_TMP/once"
    ok sh "$ROOT/scripts/patches/wifi-band-order.sh" "$wifi"
    assert_same "$TEST_TMP/once" "$generated"
    assert_same "$upstream" "$wifi/package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
    rewrite "$wifi/package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc" 'let band_name = filter(bands_order, (b) => radio.bands[b])[0];' 'let band_name = "2G";'
    reject sh "$ROOT/scripts/patches/wifi-band-order.sh" "$wifi"
    assert_same "$TEST_TMP/once" "$generated"
}
run_tests "$@"
