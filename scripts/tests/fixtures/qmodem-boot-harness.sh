#!/bin/sh
# Test-only sysfs, config and elapsed-time substitutes for the real init script.
config_get()
{
    value=
    case "$2:$3" in
        main:scan_delay) value=${TEST_SCAN_DELAY:-0} ;;
        6_1:data_interface) value=usb ;;
        6_1:state) value=enabled ;;
        6_1:name) value=fm350-gl ;;
        6_1:network) value=${TEST_NET_NAME:-eth2} ;;
        6_1:at_port) value=/dev/ttyUSB1 ;;
        6_1:path)
            value="$TEST_BOOT_ROOT/sys/bus/usb/devices/6-1"
            [ "${TEST_STALE_PATH:-0}" = 1 ] && value="$TEST_BOOT_ROOT/sys/bus/usb/devices/9-9"
            ;;
        *) value=${4:-} ;;
    esac
    # Variable names are fixed identifiers supplied by the production helper.
    eval "$1=\$value"
}
config_load() { :; }
config_foreach()
{
    callback=$1
    shift 2
    tick=$(cat "$TEST_BOOT_ROOT/tick")
    [ "$tick" -ge "${TEST_RECOGNIZED_AT:-9999}" ] || return 0
    "$callback" 6_1 "$@"
}
logger() { printf '%s\n' "$*" >> "$TEST_BOOT_ROOT/log"; }
uci()
{
    tick=$(cat "$TEST_BOOT_ROOT/tick")
    case "$*" in
        '-q get qmodem.main.enable_usb_scan')
            if [ "$tick" -ge "${TEST_DISABLE_AT:-9999}" ]; then echo 0; else echo 1; fi
            ;;
        '-q get qmodem.main.block_auto_probe') echo "${TEST_BLOCK_AUTO:-0}" ;;
        *) return 1 ;;
    esac
}
make_network()
{
    slot=$1 net=$2 driver=$3
    base="$TEST_BOOT_ROOT/sys/devices/platform/usb6/$slot"
    mkdir -p "$base/$slot:1.0" "$TEST_BOOT_ROOT/sys/class/net/$net" "$TEST_BOOT_ROOT/sys/drivers/$driver"
    ln -sf "$TEST_BOOT_ROOT/sys/drivers/$driver" "$base/$slot:1.0/driver"
    ln -sf "$base/$slot:1.0" "$TEST_BOOT_ROOT/sys/class/net/$net/device"
    ln -sf "$base" "$TEST_BOOT_ROOT/sys/bus/usb/devices/$slot"
}
sleep()
{
    printf '%s\n' "$1" >> "$TEST_BOOT_ROOT/sleeps"
    tick=$(cat "$TEST_BOOT_ROOT/tick")
    tick=$((tick + $1))
    printf '%s\n' "$tick" > "$TEST_BOOT_ROOT/tick"
    if [ "$tick" -ge "${TEST_NET_READY_AT:-0}" ] && [ "${TEST_NO_NETWORK:-0}" != 1 ]; then
        make_network 6-1 "${TEST_NET_NAME:-eth2}" rndis_host
    fi
}

if [ "${TEST_NET_READY_AT:-0}" = 0 ] && [ "${TEST_NO_NETWORK:-0}" != 1 ]; then
    make_network 6-1 "${TEST_NET_NAME:-eth2}" rndis_host
fi
if [ "${TEST_SECOND_NETWORK:-0}" = 1 ]; then make_network 6-2 eth3 cdc_mbim; fi
if [ "${TEST_OTHER_NETWORK:-0}" = 1 ]; then make_network 6-4 eth9 r8152; fi

. "$TEST_BOOT_INIT"
if [ "${TEST_HOLD_LOCK:-0}" = 1 ]; then
    exec 8>"$TEST_BOOT_ROOT/lock/qmodem-boot-usb-scan.lock"
    flock -n 8 || exit 1
fi
_scan_usb
wait
