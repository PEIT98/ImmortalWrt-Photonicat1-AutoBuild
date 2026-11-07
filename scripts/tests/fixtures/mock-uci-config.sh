#!/bin/sh
# A private staged UCI subset; no host configuration is read or committed.
set -eu
root=${PHOTONICAT_PACKAGE_ROOT:-${SWRT_UPGRADE_ROOT:-${AURORA_UPDATE_ROOT:-}}}
case "$root" in
    ''|/) echo 'mock UCI requires a private test root' >&2; exit 1 ;;
esac
config="$root/etc/config"
staging="$root/global-uci"
while [ $# -gt 0 ]; do
    case "$1" in
        -c) config=$2; shift 2 ;;
        -t) staging=$2; shift 2 ;;
        -q) shift ;;
        *) break ;;
    esac
done
action=$1; key=$2
package=${key%%.*}; package=${package%%=*}
case "$package" in photonicat_packages|swrt_upgrade|aurora_update) ;; *) exit 1 ;; esac
file="$config/$package"; delta="$staging/$package"
values='{}'
if [ -f "$file" ]; then
    values=$(awk -F "'" '/^[[:space:]]*option / {key=$1; sub(/^[[:space:]]*option /,"",key); sub(/[[:space:]]+$/,"",key); print key "\t" $2}' "$file" | jq -Rn '[inputs|split("\t")|{key:.[0],value:.[1]}]|from_entries')
fi
case "$action" in
    get)
        option=${key##*.}
        printf '%s\n' "$values" | jq -er --arg k "$option" '.[$k] // empty'
        ;;
    set)
        mkdir -p "$staging"
        if [ -f "$delta" ]; then values=$(cat "$delta"); fi
        case "$key" in
            "$package.main."*)
                setting=${key%%=*}; value=${key#*=}; option=${setting##*.}
                printf '%s\n' "$values" | jq --arg k "$option" --arg v "$value" '.[$k]=$v' > "$delta"
                ;;
            *) printf '%s\n' "$values" > "$delta" ;;
        esac
        ;;
    commit)
        [ ! -e "$root/uci-fail" ] || exit 7
        mkdir -p "$config"
        { printf "config settings 'main'\n"; jq -r 'to_entries[]|"\toption \(.key) '\''\(.value)'\''"' "$delta"; } > "$file"
        rm "$delta"
        ;;
    *) exit 1 ;;
esac
