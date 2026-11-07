#!/bin/bash
# FM350 automatic APN must use the matching PDP and leave other modems alone.
source "$(dirname "$0")/common.sh"
setup() {
    modem_config=6_1
    pdp_index=3
    at_port=/dev/ttyUSB1
    apn=auto
    test_model=fm350-gl
    cgdcont=''
    contrdp=''
    test_imsi=''
    . "$ROOT/patches/qmodem/fm350-auto-apn.sh"
}
uci() { [[ $* == '-q get qmodem.6_1.name' ]] && printf '%s\n' "$test_model"; }
at() {
    printf '%s\n' "$2" >> "$TEST_TMP/at-calls"
    case "$2" in
        'AT+CGDCONT?') printf '%s\n' "$cgdcont" ;;
        AT+CGCONTRDP) printf '%s\n' "$contrdp" ;;
        AT+CIMI) printf '%s\n' "$test_imsi" ;;
    esac
}
m_debug() { :; }
test_current_pdp_context() {
    cgdcont='+CGDCONT: 1,"IP","ims"
+CGDCONT: 2,"IP","other"
+CGDCONT: 3,"IP","internet"'
    pwrt_fm350_auto_apn
    assert_eq internet "$apn"
    assert_eq 1 "$(wc -l < "$TEST_TMP/at-calls")"
}
test_fallback_to_active_context() {
    cgdcont='+CGDCONT: 3,"IP","ims"'
    contrdp='+CGCONTRDP: 2,5,"other"
+CGCONTRDP: 3,5,"mobile.data"'
    pwrt_fm350_auto_apn
    assert_eq mobile.data "$apn"
    assert_eq 2 "$(wc -l < "$TEST_TMP/at-calls")"
}
test_imsi_fallback() {
    test_imsi='460011234567890'
    pwrt_fm350_auto_apn
    assert_eq 3gnet "$apn"
    assert_eq 3 "$(wc -l < "$TEST_TMP/at-calls")"
}
test_manual_apn_unchanged() {
    apn=custom.net
    pwrt_fm350_auto_apn
    assert_eq custom.net "$apn"
    assert_absent "$TEST_TMP/at-calls"
}
test_other_modems_unchanged() {
    test_model=rm520n-gl
    pwrt_fm350_auto_apn
    assert_eq auto "$apn"
    assert_absent "$TEST_TMP/at-calls"
}
test_invalid_data_not_used() {
    cgdcont='+CGDCONT: 3,"IP","ims"'
    contrdp='+CGCONTRDP: 3,5,"invalid;command"'
    test_imsi='999991234567890'
    pwrt_fm350_auto_apn
    assert_eq auto "$apn"
}
run_tests "$@"
