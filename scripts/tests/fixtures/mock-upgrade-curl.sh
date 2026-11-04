#!/bin/sh
set -eu
root=$SWRT_UPGRADE_ROOT
output=
previous=
for arg do
    if [ "$previous" = -o ]; then output=$arg; fi
    previous=$arg
    url=$arg
done
printf '%s\n' "$url" >> "$root/curl.log"
[ ! -e "$root/network-fail" ] || exit 22
case "$url" in
    *api.github.com*) source="$root/fixtures/release.json" ;;
    */SHA256SUMS.txt) source="$root/fixtures/sha256sums" ;;
    *)
        if [ -f "$root/download-delay" ]; then sleep 0.6; fi
        source="$root/fixtures/image"
        ;;
esac
cp "$source" "$output"
