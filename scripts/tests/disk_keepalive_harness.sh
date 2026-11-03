#!/bin/sh
# Root required only for the loop-device test. Everything is under a new /tmp
# directory, and no real USB disk or production UCI configuration is used.
set -eu
library=${1:?path to common.sh}
library=$(readlink -f "$library")
. "$library"
work=$(mktemp -d /tmp/swrt-disk-qa.XXXXXX)
loop=
worker_pid=
cleanup() {
    if [ -n "$worker_pid" ]; then kill "$worker_pid" 2>/dev/null || :; wait "$worker_pid" 2>/dev/null || :; fi
    [ -z "$loop" ] || losetup -d "$loop"
    rm -rf "$work"
}
trap cleanup EXIT
SYS_BLOCK=$work/sys
DEV_ROOT=$work/dev
STATE=$work/state
mkdir -p "$SYS_BLOCK" "$DEV_ROOT" "$STATE"
logger() { :; }
device() {
    slot=$1
    identity=$2
    usb=$work/devices/usb99/99-$slot
    mkdir -p "$usb/disk" "$SYS_BLOCK/sd$slot"
    echo 174c >"$usb/idVendor"
    echo 0 >"$usb/disk/type"
    echo ASM1153E-QA >"$usb/disk/model"
    echo QA >"$usb/disk/vendor"
    echo "$identity" >"$usb/disk/wwid"
    echo 32768 >"$SYS_BLOCK/sd$slot/size"
    ln -s "$usb/disk" "$SYS_BLOCK/sd$slot/device"
}
device a disk-alpha
device b disk-beta
alpha=$(inventory | jq -r '.[]|select(.name=="sda")|.id')
beta=$(inventory | jq -r '.[]|select(.name=="sdb")|.id')
valid_id "$alpha"
[ "$alpha" != "$beta" ]
inventory | jq -e 'length==2 and all(.[];.selectable)' >/dev/null
# A cloned USB/SCSI identity must not target both disks.
echo disk-alpha >"$work/devices/usb99/99-b/disk/wwid"
inventory | jq -e 'length==2 and all(.[];.selectable==false)' >/dev/null
if resolve "$alpha"; then echo 'FAIL: duplicate identity resolved'; exit 1; fi
echo disk-beta >"$work/devices/usb99/99-b/disk/wwid"
if resolve '/dev/mmcblk0'; then echo 'FAIL: injected device path accepted'; exit 1; fi
# USB numbering changes: identity follows the original disk to its new sdX.
mv "$SYS_BLOCK/sda" "$SYS_BLOCK/sdc"
resolve "$alpha" | jq -e '.name=="sdc"' >/dev/null
# Unplugging must not fall through to an unrelated disk at the old path.
mv "$SYS_BLOCK/sdc" "$work/disconnected"
if resolve "$alpha"; then echo 'FAIL: offline disk resolved'; exit 1; fi
mv "$work/disconnected" "$SYS_BLOCK/sdc"
echo 'PASS: inventory, duplicate identities, rename, unplug and path rejection'
[ "${SWRT_DISK_QA_IDENTITY_ONLY:-0}" != 1 ] || exit 0

# Exercise actual O_DIRECT block reads with a RAM-backed disposable loop device.
dd if=/dev/urandom of="$work/disk.img" bs=1048576 count=16 2>/dev/null
before=$(sha256sum "$work/disk.img" | cut -d' ' -f1)
loop=$(losetup --find --show "$work/disk.img")
ln -s "$loop" "$DEV_ROOT/sdc"
reads_before=$(awk '{print $1}' "/sys/class/block/${loop##*/}/stat")
read_disk "$alpha" | jq -e '.ok==true' >/dev/null
read_disk "$alpha" | jq -e '.ok==true' >/dev/null
reads_after=$(awk '{print $1}' "/sys/class/block/${loop##*/}/stat")
[ "$reads_after" -gt "$reads_before" ]
[ "$(sha256sum "$work/disk.img" | cut -d' ' -f1)" = "$before" ]
state_read "$alpha" | jq -e '.count==2 and .last_success>0 and .error==""' >/dev/null
# A direct-read failure must be shown and must not increment success or fall
# back to a cached read. This also exercises recovery on the next attempt.
DD=/bin/false
read_disk "$alpha" | jq -e '.ok==false' >/dev/null
state_read "$alpha" | jq -e '.count==2 and (.error|length)>0' >/dev/null
cat >"$work/short-read" <<'EOF'
#!/bin/sh
echo '0+1 records in' >&2
exit 0
EOF
chmod 755 "$work/short-read"
DD=$work/short-read
read_disk "$alpha" | jq -e '.ok==false' >/dev/null
state_read "$alpha" | jq -e '.count==2' >/dev/null
# shellcheck disable=SC2034
DD=$(command -v dd)
read_disk "$alpha" | jq -e '.ok==true' >/dev/null
state_read "$alpha" | jq -e '.count==3 and .error==""' >/dev/null
echo 'PASS: block-layer reads increased; disk checksum unchanged; error/recovery recorded'

# Invalid RPC input must not reach any UCI write or service operation.
uci() {
    case "$*" in *batch*|*commit*|*add_list*) touch "$work/uci-write"; return 1 ;; esac
    return 0
}
rejected() {
    printf '%s' "$1" | configure | jq -e '.ok==false' >/dev/null
    [ ! -f "$work/uci-write" ]
}
base='{"enabled":false,"interval":60,"usb_awake":true,"devices":[]}'
rejected '{}'
rejected "$(printf '%s' "$base" | jq '.enabled=true')"
for bad in 0 9 3601 1.5 '"60"'; do
    rejected "$(printf '%s' "$base" | jq --argjson bad "$bad" '.interval=$bad')"
done
rejected "$(printf '%s' "$base" | jq '.devices=["/dev/mmcblk0"]')"
rejected "$(printf '%s' "$base" | jq --arg id "$alpha" '.devices=[$id+"\n"]')"
rejected "$(printf '%s' "$base" | jq --arg id "$alpha" '.devices=[$id,$id]')"
rejected "$(printf '%s\n%s' "$base" "$base")"
echo 'PASS: bounds, types, empty selection, newline/path injection and concatenated JSON rejected before configuration writes'

# Real scheduling, locking and stopping, using only the fixture/loop device.
cat >"$work/worker" <<'EOF'
#!/bin/sh
. "$QA_LIBRARY"
SYS_BLOCK=$QA_WORK/sys
DEV_ROOT=$QA_WORK/dev
STATE=$QA_WORK/state
SELF=$QA_WORK/worker
read_config() { enabled=1; interval=10; usb_awake=0; ids=$QA_ALPHA; }
logger() { :; }
case "$1" in daemon) daemon_run ;; read) read_disk "$2" ;; status) status ;; esac
EOF
chmod 755 "$work/worker"
rm -f "$(state_path "$alpha")"
export QA_LIBRARY="$library" QA_WORK="$work" QA_ALPHA="$alpha"
"$work/worker" daemon >"$work/worker.log" 2>&1 &
worker_pid=$!
# shellcheck disable=SC2034
for unused in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    sleep 1
    [ "$(state_read "$alpha" | jq .count)" -lt 2 ] || break
done
"$work/worker" status | jq -e '.enabled==true and .running==true and .runtime[0].count>=2' >/dev/null
kill "$worker_pid"
wait "$worker_pid"
worker_pid=
count=$(state_read "$alpha" | jq .count)
sleep 1
[ "$(state_read "$alpha" | jq .count)" = "$count" ]
[ ! -f "$STATE/pid" ]
echo 'PASS: background daemon performed repeated timed direct reads, reported running state and stopped cleanly'
