# 插入官方 qmodem_init；仅处理启动时的 USB 扫描，不修改拨号配置。
_boot_usb_scan_allowed()
{
    [ "$(uci -q get qmodem.main.block_auto_probe)" != 1 ] &&
    [ "$(uci -q get qmodem.main.enable_usb_scan)" != 0 ]
}

_boot_usb_networks()
{
    local net path driver
    for net in /sys/class/net/*; do
        path=$(readlink -f "$net/device") || continue
        case "$path" in */usb[0-9]*/*) ;; *) continue ;; esac
        driver=$(readlink "$net/device/driver") || continue
        case "${driver##*/}" in
            qmi_wwan*|cdc_mbim|*cdc_ncm*|cdc_ether|rndis_host)
                printf '%s\n' "${net##*/}"
                ;;
        esac
    done
}

_boot_usb_match_modem()
{
    local section="$1" wanted="$2" kind state name networks at_port path net device
    config_get kind "$section" data_interface
    config_get state "$section" state
    config_get name "$section" name
    config_get networks "$section" network
    config_get at_port "$section" at_port
    config_get path "$section" path
    [ "$kind" = usb ] && [ "$state" = enabled ] &&
        [ -n "$name" ] && [ -n "$at_port" ] && [ -n "$path" ] || return 0
    path=$(readlink -f "$path") || return 0
    for net in $networks; do
        [ "$net" = "$wanted" ] || continue
        device=$(readlink -f "/sys/class/net/$net/device") || continue
        case "$device" in "$path"/*) boot_usb_known=1 ;; esac
    done
}

_boot_usb_modem_missing()
{
    local networks net boot_usb_known
    networks=$(_boot_usb_networks)
    [ -n "$networks" ] || return 0
    config_load qmodem
    for net in $networks; do
        boot_usb_known=0
        config_foreach _boot_usb_match_modem modem-device "$net"
        [ "$boot_usb_known" = 1 ] || return 0
    done
    return 1
}

_queue_ready_usb_scan()
{
    local scan_delay
    config_get scan_delay main scan_delay 0
    case "$scan_delay" in ''|*[!0-9]*) scan_delay=0 ;; esac
    mkdir -p /var/lock || return 1
    (
        # A start/restart while this helper is active must not create another loop.
        flock -n 9 || exit 0
        local attempts=0 networks
        while [ "$attempts" -lt 60 ]; do
            _boot_usb_scan_allowed || exit 0
            networks=$(_boot_usb_networks)
            if [ -n "$networks" ] &&
               /usr/bin/modem_scanc status >/dev/null 2>&1 &&
               /usr/bin/modem_scanc scan usb "$scan_delay" >/dev/null 2>&1; then
                logger -t modem_init "USB network ready; queued boot scan: $networks"
                [ "$scan_delay" -eq 0 ] || sleep "$scan_delay"
                sleep 15
                _boot_usb_scan_allowed || exit 0
                if ! _boot_usb_modem_missing; then
                    logger -t modem_init 'USB modem recognized; skip boot rescan'
                    exit 0
                fi
                # Use the existing daemon; a stopped service must stay stopped.
                /usr/bin/modem_scanc status >/dev/null 2>&1 || exit 0
                if /usr/bin/modem_scanc scan usb 0 >/dev/null 2>&1; then
                    logger -t modem_init 'USB modem still missing after 15 seconds; queued one boot rescan'
                else
                    logger -t modem_init 'Failed to queue USB boot rescan'
                fi
                exit 0
            fi
            attempts=$((attempts + 1))
            sleep 1
        done
        logger -t modem_init 'USB boot scan stopped after 60 seconds: modem network or scan daemon unavailable'
    ) 9>/var/lock/qmodem-boot-usb-scan.lock &
}
