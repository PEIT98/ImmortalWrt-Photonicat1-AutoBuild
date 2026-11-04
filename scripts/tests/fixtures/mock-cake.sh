#!/bin/sh
set -eu
state=$CAKE_TEST_STATE
name=${0##*/}
jq -cn --args '$ARGS.positional' -- "$name" "$@" >> "$CAKE_TEST_CALLS"
while [ "${1:-}" = -q ]; do shift; done
case "$name" in
uci)
    case "$1" in
        get) jq -er --arg k "$2" '.uci[$k]//empty' "$state" ;;
        show) jq -r '.queues[]|"sqm.\(.)=queue"' "$state" ;;
        set|delete|commit)
            [ "${CAKE_TEST_WRITABLE:-0}" = 1 ] || exit 1
            case "$1" in
            set) k=${2%%=*}; v=${2#*=}; jq --arg k "$k" --arg v "$v" '.uci[$k]=$v' "$state" > "$state.next"; mv "$state.next" "$state" ;;
            delete) jq --arg k "$2" 'del(.uci[$k])' "$state" > "$state.next"; mv "$state.next" "$state" ;;
            esac
            ;;
        *) exit 1 ;;
    esac
    ;;
ubus) jq '.status' "$state" ;;
tc)
    if [ "$1 $2" = 'qdisc show' ]; then
        for device do :; done
        if jq -e --arg d "$device" '.cake_devices|index($d)' "$state" >/dev/null; then echo 'qdisc cake 8001: root refcnt 2 bandwidth 20Mbit'; else echo 'qdisc fq_codel 0: root refcnt 2'; fi
    elif [ "$1 $2 $3" = '-j filter show' ]; then jq '.filters' "$state"
    else exit 1
    fi
    ;;
jsonfilter)
    while [ "$1" != -e ]; do shift; done
    case "$2" in
    '@.up') jq -r .up ;;
    '@.l3_device') jq -r '.l3_device//""' ;;
    '@[*].options.actions[*].to_dev') jq -r '.[].options.actions[]|.to_dev//empty' ;;
    *) exit 1 ;;
    esac
    ;;
cake-service) : ;;
*) exit 1 ;;
esac
