#!/bin/sh
# Host-side literal text edits. Validate staged copies before touching sources.
pc_fail() { printf '::error::%s\n' "$*" >&2; exit 1; }
pc_init() {
    PC_TMP=$(mktemp -d)
    PC_SEQ=0
    trap 'rm -rf "$PC_TMP"' EXIT
    trap 'exit 1' HUP INT TERM
}
pc_load() {
    [ -f "$1" ] || pc_fail "缺少源码文件：$1"
    [ -s "$1" ] || pc_fail "源码文件为空：$1"
    PC_SEQ=$((PC_SEQ + 1))
    printf '%s\n' "$1" > "$PC_TMP/target.$PC_SEQ"
    PC_WORK="$PC_TMP/work.$PC_SEQ"
    cp -p "$1" "$PC_WORK"
}
pc_count() {
    PC_TEXT=$1 awk 'BEGIN { RS="\0"; needle=ENVIRON["PC_TEXT"] }
        { s=$0; while (length(needle) && (p=index(s,needle))) { n++; s=substr(s,p+length(needle)) } }
        END { print n+0 }' "$PC_WORK"
}
pc_require() {
    [ "$(pc_count "$1")" -eq "${2:-1}" ] || pc_fail "${3:-源码锚点缺失或重复}"
}
pc_awk() {
    awk "$@" "$PC_WORK" > "$PC_TMP/next" || pc_fail '上游布局变化，请先核对源码'
    cat "$PC_TMP/next" > "$PC_WORK"
}
pc_replace() {
    # Environment carries literal strings without awk -v escape expansion.
    PC_OLD=$1 PC_NEW=$2 PC_LABEL=${3:-源码锚点} pc_awk '
    function count(s,t, n,p) { n=0; while(length(t) && (p=index(s,t))) { n++; s=substr(s,p+length(t)) } return n }
    function replace(s,a,b, p) { p=index(s,a); return substr(s,1,p-1) b substr(s,p+length(a)) }
    BEGIN { RS="\0"; ORS=""; old=ENVIRON["PC_OLD"]; new=ENVIRON["PC_NEW"] }
    {
        seen=1
        if (length(new) && count($0,new)==1 && !count(replace($0,new,""),old)) { print; next }
        if (!length(old) || count($0,old)!=1 || (length(new) && count($0,new))) {
            print ENVIRON["PC_LABEL"] " 上游布局变化，请先核对源码\n" > "/dev/stderr"; exit 1
        }
        print replace($0,old,new)
    }
    END { if (!seen) exit 1 }'
}
pc_commit() {
    pc_i=1
    while [ "$pc_i" -le "$PC_SEQ" ]; do
        pc_target=$(cat "$PC_TMP/target.$pc_i")
        if ! cmp -s "$PC_TMP/work.$pc_i" "$pc_target"; then
            cat "$PC_TMP/work.$pc_i" > "$pc_target"
        fi
        pc_i=$((pc_i + 1))
    done
}
