#!/bin/bash
# 在官方拨号源码中检查入口与幂等性，模拟 AT 回复验证型号及 APN 边界。
source "$(dirname "$0")/common.sh"
FEED=$(realpath "${1:?需要 QModem Feed 目录}")
setup() {
    feed="$TEST_TMP/feed"
    dial=application/qmodem/files/usr/share/qmodem/modem_dial.sh
    fragment=application/qmodem/files/usr/share/qmodem/fixes/fm350-auto-apn/auto-apn.sh
    mkdir -p "$feed/$(dirname "$dial")"
    git -C "$FEED" show "HEAD:$dial" > "$feed/$dial"
    patch="$ROOT/patches/qmodem/fix-fm350-auto-apn.sh"
    ok sh "$patch" "$feed"
    MOCK_MODEL=fm160-eau
    MOCK_CONTEXT=
    MOCK_DYNAMIC=
    MOCK_IMSI=
    modem_config=6_1
    pdp_index=0
    apn=
    at_port=/dev/mock
    : > "$TEST_TMP/at-calls"
    . "$feed/$fragment"
    MOCK_MODEL=fm350-gl
}
uci() { printf '%s\n' "$MOCK_MODEL"; }
at() {
    printf '%s\n' "$2" >> "$TEST_TMP/at-calls"
    case "$2" in
        'AT+CGDCONT?') printf '%s\n' "$MOCK_CONTEXT" ;;
        'AT+CGCONTRDP') printf '%s\n' "$MOCK_DYNAMIC" ;;
        'AT+CIMI') printf '%s\n' "$MOCK_IMSI" ;;
        *) return 1 ;;
    esac
}
m_debug() { printf '%s\n' "$*" >> "$TEST_TMP/apn-log"; }
test_other_models_and_manual_apn_are_untouched() {
    local model
    for model in fm160-eau fm650 rm520n-gl; do
        MOCK_MODEL=$model
        pwrt_fm350_auto_apn
        assert_eq '' "$apn"
    done
    MOCK_MODEL=fm350-gl
    apn=private.example
    pwrt_fm350_auto_apn
    assert_eq private.example "$apn"
    [[ ! -s $TEST_TMP/at-calls ]] || fail '其他型号或手填 APN 发出了 AT 查询'
}
test_recovers_reported_data_apn_without_touching_ims() {
    MOCK_CONTEXT='+CGDCONT: 0,"IPV4V6","",""
+CGDCONT: 1,"IPV4V6","ims",""'
    MOCK_DYNAMIC='+CGCONTRDP: 1,,"ims",""
+CGCONTRDP: 0,,"cmnet",""'
    pwrt_fm350_auto_apn
    assert_eq cmnet "$apn"
    assert_eq 0 "$pdp_index"
    assert_not_has "$TEST_TMP/at-calls" 'AT+CGDCONT='
    assert_not_has "$TEST_TMP/at-calls" 'AT+CGACT='
}
test_preserves_custom_apn_and_selected_pdp() {
    pdp_index=3
    MOCK_CONTEXT='+CGDCONT: 0,"IPV4V6","wrong",""
+CGDCONT: 3,"IPV4V6","private.example",""'
    pwrt_fm350_auto_apn
    assert_eq private.example "$apn"
    assert_eq 3 "$pdp_index"
    assert_not_has "$TEST_TMP/at-calls" 'AT+CIMI'
}
test_filters_service_and_invalid_apns_and_other_pdp() {
    local value
    MOCK_DYNAMIC='+CGCONTRDP: 1,,"wrong",""'
    for value in ims ims.mnc000.mcc460.gprs sos xcap 'bad;AT+CFUN=0'; do
        apn=
        MOCK_CONTEXT="+CGDCONT: 0,\"IPV4V6\",\"$value\",\"\""
        pwrt_fm350_auto_apn
        assert_eq '' "$apn"
    done
}
test_sim_carrier_fallback_and_unknown_sim() {
    local prefix
    for prefix in 46000 46002 46007 46008 46013; do
        apn=auto
        MOCK_IMSI="${prefix}1234567890"
        pwrt_fm350_auto_apn
        assert_eq cmnet "$apn"
    done
    apn=; MOCK_IMSI=460011234567890
    pwrt_fm350_auto_apn
    assert_eq 3gnet "$apn"
    apn=; MOCK_IMSI=460111234567890
    pwrt_fm350_auto_apn
    assert_eq ctnet "$apn"
    apn=; MOCK_IMSI=999991234567890
    pwrt_fm350_auto_apn
    assert_eq '' "$apn"
}
test_build_hook_is_idempotent_and_keeps_upstream_code() {
    cp "$feed/$dial" "$TEST_TMP/once"
    ok sh "$patch" "$feed"
    assert_same "$TEST_TMP/once" "$feed/$dial"
    assert_same "$ROOT/patches/qmodem/fm350-auto-apn.sh" "$feed/$fragment"
    sed '/# Pwrt-FM350-APN$/d' "$feed/$dial" > "$TEST_TMP/without-hook"
    git -C "$FEED" show "HEAD:$dial" > "$TEST_TMP/original"
    assert_same "$TEST_TMP/original" "$TEST_TMP/without-hook"
}
test_changed_layout_is_rejected_without_writing() {
    git -C "$FEED" show "HEAD:$dial" > "$feed/$dial"
    rm "$feed/$fragment"
    rewrite "$feed/$dial" 'at_dial()' 'at_dial_changed()'
    cp "$feed/$dial" "$TEST_TMP/before"
    reject sh "$patch" "$feed"
    assert_same "$TEST_TMP/before" "$feed/$dial"
    assert_absent "$feed/$fragment"
}
run_tests "$@"
