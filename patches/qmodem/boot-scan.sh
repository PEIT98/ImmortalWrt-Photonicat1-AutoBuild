# 由 qmodem_init 的 boot() 加载；只调度官方扫描入口，不改拨号配置。
pwrt_qmodem_net_signature()
{
    local entry device path
    for entry in /sys/class/net/*; do
        device=${entry##*/}
        case "$device" in usb*|eth*|wwan*|rmnet*|mhi_hwip*) ;; *) continue ;; esac
        path=$(readlink -f "$entry/device") || continue
        case "$path" in
            */usb*|*/pci*) printf '%s=%s\n' "$device" "$path" ;;
        esac
    done
}

pwrt_qmodem_wait_networks()
{
    local initial previous current elapsed=0 stable=0
    config_get initial main start_delay 0
    case "$initial" in ''|*[!0-9]*) initial=15 ;; esac
    [ "$initial" -ge 15 ] || initial=15
    sleep "$initial"
    previous=$(pwrt_qmodem_net_signature)
    # 网卡连续 3 秒不再变化后扫描；最多额外等 15 秒，避免无模组时一直等待。
    while [ "$elapsed" -lt 15 ]; do
        sleep 1
        elapsed=$((elapsed + 1))
        current=$(pwrt_qmodem_net_signature)
        if [ -n "$current" ] && [ "$current" = "$previous" ]; then
            stable=$((stable + 1))
            [ "$stable" -ge 3 ] && return 0
        else
            stable=0
        fi
        previous=$current
    done
}

pwrt_qmodem_collect_networks()
{
    local name state port network
    config_get name "$1" name
    config_get state "$1" state
    config_get port "$1" at_port
    config_get network "$1" network
    [ -n "$name" ] && [ "$state" = enabled ] && [ -c "$port" ] || return 0
    pwrt_qmodem_identified_networks="$pwrt_qmodem_identified_networks $network"
}

pwrt_qmodem_need_retry()
{
    local entry device signature
    pwrt_qmodem_identified_networks=
    config_load qmodem
    config_foreach pwrt_qmodem_collect_networks modem-device
    [ -n "$pwrt_qmodem_identified_networks" ] || return 0
    signature=$(pwrt_qmodem_net_signature)
    [ -n "$signature" ] || return 0
    # 逐个核对网卡，避免一张模组已识别就漏掉其他模组。
    for entry in $signature; do
        device=${entry%%=*}
        case " $pwrt_qmodem_identified_networks " in
            *" $device "*) ;;
            *) return 0 ;;
        esac
    done
    return 1
}

pwrt_qmodem_scan_all()
{
    /usr/bin/modem_scanc scan all
}

pwrt_qmodem_boot_scan()
{
    local failed=0
    pwrt_qmodem_wait_networks
    logger -t qmodem_boot_scan '网卡等待结束，开始 USB + PCIe 全扫描'
    if ! pwrt_qmodem_scan_all; then
        failed=1
        logger -t qmodem_boot_scan '首次扫描请求失败，15 秒后重试'
    fi
    sleep 15
    if [ "$failed" -eq 1 ] || pwrt_qmodem_need_retry; then
        logger -t qmodem_boot_scan '仍有模组未识别，补扫 USB + PCIe 一次'
        pwrt_qmodem_scan_all || logger -t qmodem_boot_scan '补扫请求失败，请检查 modem_scand 日志'
    else
        logger -t qmodem_boot_scan '当前模组已识别，跳过补扫'
    fi
}
