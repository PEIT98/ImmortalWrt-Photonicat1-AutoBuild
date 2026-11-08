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
[ ! -e "$root/network-fail" ] || { printf 'fixture network error\n' >&2; exit 22; }
case "$url" in
    *api.github.com*)
        while [ -f "$root/api-block" ]; do sleep 0.03; done
        if [ -f "$root/api-fail-once" ]; then
            rm "$root/api-fail-once"
            printf 'incomplete response' > "$output"
            printf 'fixture connection interrupted\n' >&2
            exit 28
        fi
        if [ -f "$root/api-html-once" ]; then
            rm "$root/api-html-once"
            printf '<html>proxy warming up</html>\n' > "$output"
            exit 0
        fi
        source="$root/fixtures/release.json"
        ;;
    */SHA256SUMS.txt) source="$root/fixtures/sha256sums" ;;
    *)
        if [ -f "$root/download-delay" ]; then sleep 0.6; fi
        source="$root/fixtures/image"
        ;;
esac
cp "$source" "$output"
