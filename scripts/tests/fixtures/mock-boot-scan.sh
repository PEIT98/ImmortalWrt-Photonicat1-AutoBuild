#!/bin/sh
set -eu
root=$GUARD_TEST_ROOT
state="$root/state.json"
name=${0##*/}
while [ "${1:-}" = -q ]; do shift; done
get() { jq -r "$1" "$state"; }
set_state() { jq "$1" "$state" > "$root/state.next"; mv "$root/state.next" "$state"; }
event() { jq -cn --arg kind "$1" --argjson tick "$(get '.tick//0')" --argjson value "$2" '[$kind,$tick,$value]' >> "$root/events.jsonl"; }
args() { printf '%s\n' "$@" | jq -Rn '[inputs]'; }
case "$name" in
uci)
    op=$1; shift
    case "$op" in
    show)
        if [ "$(get '.hang_uci//false')" = true ]; then exec sleep 60; fi
        set_state '.tick=(.tick//0)+1'
        tick=$(get .tick)
        if [ "$(get '.tty_after//-1')" = "$tick" ]; then ln -s /dev/null "$root/dev/ttyUSB2"; fi
        if [ "$(get '.requests//0')" -gt 0 ] && [ "$(get '.complete_after//999')" -le "$tick" ]; then set_state '.configured=true'; fi
        printf "qmodem.main=main\nqmodem.main.enable_usb_scan='%s'\nqmodem.main.block_auto_probe='%s'\n" "$(get '.enabled//"1"')" "$(get '.blocked//"0"')"
        if [ "$(get '(.configured//false) or (.fixed//false) or (.wrong_at//false)')" = true ]; then cat "$root/device.conf"; fi
        if [ "$(get '.active_other//false')" = true ]; then printf "qmodem.custom=modem-device\nqmodem.custom.state='enabled'\nqmodem.custom.network='wan_modem'\n"; fi
        ;;
    get) jq -er --arg key "$1" '.values[$key]//empty' "$state" ;;
    set)
        key=${1%%=*}; value=${1#*=}
        jq --arg key "$key" --arg value "$value" '.values[$key]=$value' "$state" > "$root/state.next"
        mv "$root/state.next" "$state"
        event set "$(jq -cn --arg v "$1" '$v')"
        ;;
    commit) event commit "$(jq -cn --arg v "$1" '$v')" ;;
    *) exit 1 ;;
    esac
    ;;
modem_scanc)
    if [ "$*" = status ]; then
        jq '{queue:0,active:(if ((.busy_until//0)>=(.tick//0)) or (.mode=="queued" and (.requests//0)>0 and (.configured//false|not)) then 1 else 0 end),workers:4}' "$state"
    else
        event scan "$(args "$@")"
        set_state '.requests=(.requests//0)+1|if .mode=="immediate" then .configured=true else . end'
        printf '{"code":0,"message":"queued"}\n'
    fi
    ;;
qmodem_init)
    event init "$(args "$@")"
    set_state 'if .mode=="recover" then .configured=true else . end'
    ;;
guard_init) event enable "$(args "$@")" ;;
logger) event log "$(args "$@")" ;;
*) exit 1 ;;
esac
