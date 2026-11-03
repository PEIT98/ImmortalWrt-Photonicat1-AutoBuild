#!/bin/sh
# Only the entry point sets these paths. The library is also sourced by tests.
SYS_BLOCK=/sys/class/block
DEV_ROOT=/dev
STATE=/var/run/swrt-disk-keepalive
SELF=/usr/libexec/swrt-disk-keepalive
DD=$(command -v dd)
TIMEOUT=/usr/bin/timeout

fail() { jq -nc --arg message "$1" '{ok:false,message:$message}'; }
read_value() { head -c 512 "$1" 2>/dev/null | tr -d '\000\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }
valid_id() {
    case "$1" in ''|*[!a-z0-9-]*) return 1 ;; esac
    printf '%s\n' "$1" | grep -Eq '^(wwid|serial)-[0-9a-f]{64}$'
}

# No blkid, SMART or filesystem reads here: opening the page must not wake disks.
inventory() {
    for sys in "$SYS_BLOCK"/sd*; do
        if [ ! -d "$sys" ] || [ -e "$sys/partition" ]; then continue; fi
        [ "$(read_value "$sys/device/type")" = 0 ] || continue
        dev=$(readlink -f "$sys/device")
        case "$dev" in */usb[0-9]*/*) ;; *) continue ;; esac
        name=${sys##*/}
        case "$name" in sd*[!a-z]*|sd) continue ;; esac
        usb=$dev
        while [ "$usb" != / ] && [ ! -f "$usb/idVendor" ]; do usb=${usb%/*}; done
        [ -f "$usb/idVendor" ] || continue
        model=$(read_value "$sys/device/model")
        vendor=$(read_value "$sys/device/vendor")
        serial=$(read_value "$sys/device/serial")
        [ -n "$serial" ] || serial=$(read_value "$usb/serial")
        wwid=$(read_value "$sys/device/wwid")
        sectors=$(read_value "$sys/size")
        case "$sectors" in ''|*[!0-9]*) continue ;; esac
        id=
        if [ -n "$wwid" ]; then
            id=wwid-$(printf '%s' "$wwid" | sha256sum | cut -d' ' -f1)
        elif [ -n "$serial" ] && ! printf '%s' "$serial" | grep -Eq '^(0+|1234567890|0123456789|0123456789ABCDEF)$'; then
            id=serial-$(printf '%s\n' "$serial" "$vendor" "$model" "$sectors" | sha256sum | cut -d' ' -f1)
        fi
        driver=
        node=$dev
        while [ "$node" != "$usb" ] && [ "$node" != / ]; do
            case "$(readlink -f "$node/driver")" in */uas) driver=uas ;; */usb-storage) driver='usb-storage' ;; esac
            node=${node%/*}
        done
        mounts=$(awk -v disk="$name" '$1 ~ ("^/dev/" disk "([0-9]+)?$") {print $2}' /proc/mounts | tr '\n' ' ')
        system=false
        # Protect USB-root systems as well as this board's eMMC-root configuration.
        for part in "$sys" "$sys"/"$name"*; do
            [ -f "$part/dev" ] || continue
            if awk -v number="$(cat "$part/dev")" '$3==number && ($5=="/" || $5=="/rom" || $5=="/overlay" || $5=="/boot") {found=1} END {exit !found}' /proc/self/mountinfo; then
                system=true
            fi
        done
        jq -nc --arg id "$id" --arg name "$name" --arg model "$vendor $model" --arg serial "$serial" \
            --arg usb "$usb" --arg driver "$driver" --arg mounts "$mounts" --argjson system "$system" \
            --argjson sectors "$sectors" --arg usb_power "$(read_value "$usb/power/control")" \
            '{id:$id,name:$name,model:$model,serial:$serial,usb:$usb,driver:$driver,mounts:$mounts,
              bytes:($sectors*512),system:$system,usb_power:$usb_power}'
    done | jq -s 'group_by(.id) | map(. as $group | .[] | . + {
        selectable:(.id!="" and ($group|length)==1 and (.system|not)),
        reason:(if .system then "系统磁盘" elif .id=="" then "未提供稳定硬盘标识" elif ($group|length)>1 then "硬盘标识重复" else "" end)
    })'
}

read_config() {
    enabled=$(uci -q get swrt_disk_keepalive.main.enabled)
    interval=$(uci -q get swrt_disk_keepalive.main.interval)
    usb_awake=$(uci -q get swrt_disk_keepalive.main.usb_awake)
    case "$interval" in ''|*[!0-9]*) interval=60 ;; esac
    if [ "$interval" -lt 10 ] || [ "$interval" -gt 3600 ]; then interval=60; fi
    [ "$enabled" = 1 ] || enabled=0
    [ "$usb_awake" = 1 ] || usb_awake=0
    ids=$(uci -q get swrt_disk_keepalive.main.device | tr ' ' '\n' | grep -E '^(wwid|serial)-[0-9a-f]{64}$' | head -n 16)
}

state_path() { printf '%s/%s.json' "$STATE" "$1"; }
state_read() {
    if [ -f "$(state_path "$1")" ]; then cat "$(state_path "$1")";
    else echo '{"last_attempt":0,"last_success":0,"count":0,"error":""}'; fi
}

resolve() {
    valid_id "$1" || return 1
    inventory | jq -ce --arg id "$1" '[.[]|select(.id==$id and .selectable)] | if length==1 then .[0] else empty end'
}

# All reads and configuration changes share a flock; unplug/replug is re-resolved
# before every request. Never accept a device path supplied by the browser.
read_disk() {
    id=$1
    record=$(resolve "$id") || { fail '硬盘离线、标识重复或不可选择'; return; }
    name=$(printf '%s' "$record" | jq -r .name)
    [ -b "$DEV_ROOT/$name" ] || { fail '硬盘已断开'; return; }
    old=$(state_read "$id")
    count=$(printf '%s' "$old" | jq -r '.count // 0')
    previous=$(printf '%s' "$old" | jq -r '.last_success // 0')
    sectors=$(cat "$SYS_BLOCK/$name/size")
    # 1 MiB, moving across the first 1 GiB; always inside the whole device.
    blocks=$((sectors / 2048))
    [ "$blocks" -gt 0 ] || { fail '硬盘容量不足以读取'; return; }
    [ "$blocks" -le 1024 ] || blocks=1024
    offset=$((count % blocks))
    now=$(date +%s)
    error=
    if LC_ALL=C "$TIMEOUT" -s KILL 12 "$DD" "if=$DEV_ROOT/$name" of=/dev/null bs=1048576 count=1 "skip=$offset" iflag=direct,fullblock 2>"$STATE/read-error" &&
        grep -Fxq '1+0 records in' "$STATE/read-error"; then
        count=$((count + 1))
        last=$now
        ok=true
    else
        last=$previous
        ok=false
        error='直接读取失败，请检查硬盘、连接或驱动；未回退到缓存读取'
    fi
    jq -nc --argjson attempt "$now" --argjson last "$last" --argjson count "$count" --arg error "$error" \
        '{last_attempt:$attempt,last_success:$last,count:$count,error:$error}' >"$STATE/$id.tmp"
    mv "$STATE/$id.tmp" "$(state_path "$id")"
    before=$(printf '%s' "$old" | jq -r '.error // ""')
    if [ "$error" != "$before" ]; then
        logger -t swrt-disk-keepalive "$name: ${error:-直接读取已恢复}"
    fi
    jq -nc --argjson ok "$ok" --arg message "${error:-已完成 1 MiB 直接读取}" '{ok:$ok,message:$message}'
}

status() {
    read_config
    disks=$(inventory)
    runtime=$(for id in $ids; do
        state_read "$id" | jq -c --arg id "$id" '.+{id:$id}'
    done | jq -s .)
    running=false
    if [ -f "$STATE/pid" ]; then
        pid=$(cat "$STATE/pid")
        case "$pid" in ''|*[!0-9]*) ;; *)
            if kill -0 "$pid" 2>/dev/null && tr '\000' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -Fq "$SELF daemon"; then running=true; fi
            ;;
        esac
    fi
    jq -nc --argjson enabled "$enabled" --argjson interval "$interval" --argjson awake "$usb_awake" \
        --arg ids "$ids" --argjson devices "$disks" --argjson runtime "$runtime" --argjson running "$running" \
        '{ok:true,enabled:($enabled==1),interval:$interval,usb_awake:($awake==1),selected:($ids|split("\n")|map(select(length>0))),
          running:$running,devices:$devices,runtime:$runtime}'
}

configure() {
    request=$(head -c 16385)
    if [ "${#request}" -gt 16384 ] || ! printf '%s' "$request" | jq -se 'length==1 and (.[0]|type=="object" and
        (.enabled|type=="boolean") and (.usb_awake|type=="boolean") and
        (.interval|type=="number" and .==floor and .>=10 and .<=3600) and
        (.devices|type=="array" and length<=16 and all(.[];type=="string" and test("\\A(wwid|serial)-[0-9a-f]{64}\\z"))) and
        ((.devices|unique|length)==(.devices|length)) and ((.enabled|not) or (.devices|length)>0))' >/dev/null 2>&1; then
        fail '请选择硬盘，并输入 10～3600 秒的整数间隔'; return
    fi
    read_config
    old_ids=$ids
    enabled=$(printf '%s' "$request" | jq -r 'if .enabled then 1 else 0 end')
    interval=$(printf '%s' "$request" | jq -r .interval)
    usb_awake=$(printf '%s' "$request" | jq -r 'if .usb_awake then 1 else 0 end')
    ids=$(printf '%s' "$request" | jq -r '.devices[]')
    disks=$(inventory)
    for id in $ids; do
        # Previously selected offline disks may be retained, never silently
        # replaced by another disk reusing their old /dev/sdX name.
        if ! printf '%s' "$disks" | jq -e --arg id "$id" '.[]|select(.id==$id and .selectable)' >/dev/null; then
            if printf '%s' "$disks" | jq -e --arg id "$id" '.[]|select(.id==$id)' >/dev/null ||
                ! printf '%s\n' "$old_ids" | grep -Fxq "$id"; then
                fail '所选硬盘已变化，请刷新后重新选择'; return
            fi
        fi
    done
    uci -q batch <<EOF
set swrt_disk_keepalive.main=keepalive
set swrt_disk_keepalive.main.enabled='$enabled'
set swrt_disk_keepalive.main.interval='$interval'
set swrt_disk_keepalive.main.usb_awake='$usb_awake'
delete swrt_disk_keepalive.main.device
EOF
    for id in $ids; do uci add_list "swrt_disk_keepalive.main.device=$id"; done
    if ! uci commit swrt_disk_keepalive; then uci revert swrt_disk_keepalive; fail '配置保存失败'; return; fi
    # The daemon never uses this lock while being stopped; it is safe to restart
    # under the RPC write lock, and its next attempt waits until RPC completion.
    /etc/init.d/swrt-disk-keepalive enable
    /etc/init.d/swrt-disk-keepalive restart
    [ "$enabled" != 0 ] || daemon_cleanup
    status
}

# Remember the original USB runtime-PM policy in RAM, restore on stop/disable.
# Only leaf storage USB devices are touched; no hubs, host controller or modem.
usb_restore_one() {
    file=$1
    IFS= read -r path <"$file"
    original=$(sed -n '2p' "$file")
    stamp=$(sed -n '3p' "$file")
    case "$path" in /sys/devices/*/usb[0-9]*/*) ;; *) rm -f "$file"; return ;; esac
    if [ -f "$path/devnum" ] && [ "$(cat "$path/devnum")" = "$stamp" ]; then
        case "$original" in auto|on) printf '%s' "$original" >"$path/power/control" 2>/dev/null ;; esac
    fi
    rm -f "$file"
}

usb_reconcile() {
    desired=
    if [ "$enabled" = 1 ] && [ "$usb_awake" = 1 ]; then
        for id in $ids; do
            path=$(printf '%s' "$disks" | jq -r --arg id "$id" '.[]|select(.id==$id and .selectable)|.usb')
            [ -n "$path" ] || continue
            key=$(printf '%s' "$path" | sha256sum | cut -d' ' -f1)
            desired="$desired $key"
            file=$STATE/usb-$key
            stamp=$(cat "$path/devnum" 2>/dev/null)
            [ -n "$stamp" ] || continue
            if [ -f "$file" ] && [ "$(sed -n '3p' "$file")" != "$stamp" ]; then rm -f "$file"; fi
            if [ ! -f "$file" ]; then
                original=$(cat "$path/power/control" 2>/dev/null)
                case "$original" in auto|on) printf '%s\n%s\n%s\n' "$path" "$original" "$stamp" >"$file" ;; *) continue ;; esac
            fi
            if printf on >"$path/power/control" 2>/dev/null; then
                rm -f "$STATE/pm-error-$key"
            elif [ ! -e "$STATE/pm-error-$key" ]; then
                logger -t swrt-disk-keepalive '无法设置所选硬盘的 USB 自动挂起策略'
                touch "$STATE/pm-error-$key"
            fi
        done
    fi
    for file in "$STATE"/usb-*; do
        [ -f "$file" ] || continue
        key=${file##*/usb-}
        case " $desired " in *" $key "*) ;; *) usb_restore_one "$file" ;; esac
    done
}

daemon_cleanup() {
    for file in "$STATE"/usb-*; do [ ! -f "$file" ] || usb_restore_one "$file"; done
    rm -f "$STATE/pid"
}

daemon_run() {
    echo $$ >"$STATE/pid"
    trap 'exit 0' TERM INT
    trap daemon_cleanup EXIT
    while :; do
        read_config
        disks=$(inventory)
        usb_reconcile
        if [ "$enabled" = 1 ]; then
            now=$(date +%s)
            for id in $ids; do
                # Never retry absent or ambiguous devices with cached paths.
                printf '%s' "$disks" | jq -e --arg id "$id" '.[]|select(.id==$id and .selectable)' >/dev/null || continue
                last=$(state_read "$id" | jq -r '.last_attempt // 0')
                if [ "$now" -lt "$last" ] || [ $((now - last)) -ge "$interval" ]; then
                    flock -n "$STATE/io.lock" "$SELF" read "$id" >/dev/null
                fi
            done
        fi
        sleep 5 &
        wait $! || :
    done
}
