#!/bin/sh
# Private UCI state for first-boot migration; never accesses host configuration.
set -eu
state=$QMODEM_DEFAULTS_STATE
jq -cn --args '$ARGS.positional' -- "$@" >> "$QMODEM_DEFAULTS_CALLS"
while [ $# -gt 0 ]; do
    case "$1" in
        -q|-X) shift ;;
        -c|-t) shift 2 ;;
        *) break ;;
    esac
done
action=$1; key=$2
case "$key" in
    stock_qmodem_*)
        [ "$action" = get ] || exit 1
        jq -er --arg key "qmodem.${key#*.}" '.rom[$key] // empty' "$state"
        exit
        ;;
esac
mutate() { jq "$@" "$state" > "$state.next"; mv "$state.next" "$state"; }
case "$action" in
get) jq -er --arg key "$key" '.uci[$key] // empty | if type=="array" then join(" ") else . end' "$state" ;;
show) jq -r --arg key "$key" '.uci|to_entries[]|select(.key==$key or (.key|startswith($key+".")))|"\(.key)=\(.value)"' "$state" ;;
set)
    name=${key%%=*}; value=${key#*=}
    mutate --arg key "$name" --arg value "$value" '.uci[$key]=$value'
    ;;
add)
    index=$(jq -r '(.next//0)+1' "$state")
    section=$(printf 'cfg%03d' "$index")
    mutate --arg key "$key.$section" --arg value "$3" --argjson next "$index" '.uci[$key]=$value|.next=$next'
    printf '%s\n' "$section"
    ;;
add_list|del_list)
    name=${key%%=*}; value=${key#*=}
    mutate --arg key "$name" --arg value "$value" --arg action "$action" '
      (.uci[$key]//[]) as $old |
      (if ($old|type)=="array" then $old else ($old|split(" ")) end) as $list |
      .uci[$key]=(if $action=="add_list" then $list+[$value] else $list-[$value] end)'
    ;;
delete)
    mutate --arg key "$key" '.uci|=with_entries(select(.key!=$key and (.key|startswith($key+".")|not)))'
    ;;
rename)
    old=${key%%=*}; new="${old%%.*}.${key#*=}"
    mutate --arg old "$old" --arg new "$new" '.uci|=with_entries(if .key==$old or (.key|startswith($old+".")) then .key=($new+(.key|ltrimstr($old))) else . end)'
    ;;
commit)
    jq -e --arg package "$key" '(.fail_commit!=true) and (.fail_commit_package!=$package) and ((.fail_commit_when//"") as $marker|.uci[$marker]!="1")' "$state" >/dev/null
    ;;
revert)
    # 失败的完成标记尚未提交，模拟撤销这个新选项。
    mutate --arg key "$key" 'del(.uci[$key])'
    ;;
*) exit 1 ;;
esac
