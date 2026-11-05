# 仅补全 FM350 拨号进程中的 APN，不写入 UCI，不修改 PDP 编号。
pwrt_fm350_pick_apn()
{
    awk -F'"' -v cid="$pdp_index" -v col="$1" '
    /^\+CG(DCONT|CONTRDP):/ {
        n=$1
        sub(/^[^:]*:[[:space:]]*/, "", n)
        sub(/,.*/, "", n)
        v=$col
        if (n != cid || v !~ /^[A-Za-z0-9][A-Za-z0-9_.-]*$/) next
        if (tolower(v) ~ /(^|\.)(ims|sos|xcap|emergency)(\.|$)/) next
        print v
        exit
    }'
}
pwrt_fm350_auto_apn()
{
    local model selected imsi
    model=$(uci -q get "qmodem.$modem_config.name")
    case "$model" in fm350|fm350-gl) ;; *) return 0 ;; esac
    case "$apn" in ''|auto|AUTO) ;; *) return 0 ;; esac
    case "$pdp_index" in ''|*[!0-9]*) return 0 ;; esac

    selected=$(at "$at_port" 'AT+CGDCONT?' 2>/dev/null | pwrt_fm350_pick_apn 4)
    if [ -z "$selected" ]; then
        selected=$(at "$at_port" 'AT+CGCONTRDP' 2>/dev/null | pwrt_fm350_pick_apn 2)
    fi
    if [ -z "$selected" ]; then
        imsi=$(at "$at_port" 'AT+CIMI' 2>/dev/null | tr -d '\r' |
            awk '/^[0-9]+$/ && length($0)>=14 && length($0)<=15 {print; exit}')
        case "$imsi" in
            46000*|46002*|46007*|46008*|46013*) selected=cmnet ;;
            46001*) selected=3gnet ;;
            46011*) selected=ctnet ;;
        esac
    fi
    if [ -n "$selected" ]; then
        apn=$selected
        m_debug "FM350 auto APN: pdp=$pdp_index apn=$apn"
    else
        m_debug "FM350 auto APN: no usable APN found; manual APN required"
    fi
    return 0
}
pwrt_fm350_auto_apn
