#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Strict Rockchip Photonicat1 partition-layout safeguard.
# Prevent unattended sysupgrade from overwriting the full boot disk
# when partition locations/sizes differ from the firmware image.
set -eu
[ "$#" -eq 1 ] && [ -s "$1" ] || { echo "Missing image" >&2; exit 1; }
[ -f /lib/upgrade/common.sh ] || exit 1
[ -f /lib/functions/system.sh ] || exit 1
. /lib/functions.sh
. /lib/functions/system.sh
. /lib/upgrade/common.sh

export VERBOSE=0
export INTERACTIVE=0
export_bootdevice || { echo "Cannot resolve boot disk" >&2; exit 1; }
export_partdevice bootdisk 0 || { echo "Cannot resolve boot device" >&2; exit 1; }
[ -b "/dev/$bootdisk" ] || exit 1
TMP="$(mktemp /tmp/photonicat-ota-mbr.XXXXXX)"
trap 'rm -f "$TMP" /tmp/partmap.photonicatdisk /tmp/partmap.photonicatimage' EXIT
trap 'exit 1' HUP INT TERM
get_partitions "/dev/$bootdisk" photonicatdisk
get_image "$1" | dd of="$TMP" count=1 bs=512b 2>/dev/null
get_partitions "$TMP" photonicatimage
[ -s /tmp/partmap.photonicatdisk ] && [ -s /tmp/partmap.photonicatimage ] || {
    echo "Could not read image and disk partition maps" >&2
    exit 1
}
# Repartitioning is not permitted for OTA. Manual recovery paths can handle it.
cmp -s /tmp/partmap.photonicatdisk /tmp/partmap.photonicatimage || {
    echo "Partition layout mismatch. Full-disk reflash is blocked." >&2
    exit 1
}
echo "Partition layout matches; no full-disk repartition required."
