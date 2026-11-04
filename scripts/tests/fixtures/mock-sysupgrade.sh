#!/bin/sh
# Never calls the machine's sysupgrade or a block writer.
printf '%s\n' "$*" >> "$SWRT_UPGRADE_ROOT/sysupgrade.log"
if [ "$1" = -T ]; then
    [ ! -f "$SWRT_UPGRADE_ROOT/incompatible" ] || exit 1
    [ ! -f "$SWRT_UPGRADE_ROOT/partition-change" ] || echo 'Partition layout has changed. Full image will be written.'
    exit 0
fi
[ ! -f "$SWRT_UPGRADE_ROOT/upgrade-reject" ] || exit 7
if [ -f "$SWRT_UPGRADE_ROOT/handoff-signal" ]; then
    printf '%s\n' "$PPID" > "$SWRT_UPGRADE_ROOT/handoff-pid"
    kill -TERM "$PPID"
fi
exit 0
