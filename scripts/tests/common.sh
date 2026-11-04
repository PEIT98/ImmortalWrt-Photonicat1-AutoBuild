#!/bin/bash
# Each case runs in a fresh process with its own temporary tree.
set -euo pipefail
# ROOT is consumed by the test files sourcing this helper.
# shellcheck disable=SC2034
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
assert_eq() { [[ $1 == "$2" ]] || fail "expected [$1], got [$2]"; }
assert_has() { grep -Fq -- "$2" "$1" || fail "$1: missing [$2]"; }
assert_not_has() { if grep -Fq -- "$2" "$1"; then fail "$1: unexpected [$2]"; fi; }
assert_json() { jq -e "$2" "$1" >/dev/null || fail "$1: $2"; }
assert_file() { [[ -f $1 ]] || fail "missing file: $1"; }
assert_absent() { [[ ! -e $1 && ! -L $1 ]] || fail "unexpected file: $1"; }
assert_same() { cmp -s "$1" "$2" || fail "files differ: $1 $2"; }
capture() { if "$@" >"$OUT" 2>"$ERR"; then RC=0; else RC=$?; fi; }
ok() { capture "$@"; if [[ $RC != 0 ]]; then cat "$OUT" "$ERR" >&2; fail "command failed ($RC): $*"; fi; }
reject() { capture "$@"; [[ $RC != 0 ]] || fail "command unexpectedly succeeded: $*"; }
update_json() { jq "$2" "$1" > "$TEST_TMP/json.next"; mv "$TEST_TMP/json.next" "$1"; }
# Literal path substitution for private harnesses; no regex or eval of source data.
rewrite() {
    REWRITE_OLD=$2 REWRITE_NEW=$3 awk 'BEGIN {RS="\0";ORS="";a=ENVIRON["REWRITE_OLD"];b=ENVIRON["REWRITE_NEW"]}
    {s=$0;while(p=index(s,a)){printf "%s%s",substr(s,1,p-1),b;s=substr(s,p+length(a))}print s}' "$1" > "$TEST_TMP/rewrite.next"
    cat "$TEST_TMP/rewrite.next" > "$1"
}
run_tests() {
    if [[ -n ${TEST_CASE:-} ]]; then
        TEST_TMP=$(mktemp -d)
        OUT="$TEST_TMP/stdout"; ERR="$TEST_TMP/stderr"
        trap 'rm -rf "$TEST_TMP"' EXIT
        setup
        "$TEST_CASE"
        exit 0
    fi
    local name count=0 failed=0 log
    log=$(mktemp)
    while read -r _ _ name; do
        [[ $name == test_* ]] || continue
        if TEST_CASE=$name bash "$0" "$@" >"$log" 2>&1; then
            printf 'PASS %s\n' "$name"
        else
            printf 'FAIL %s\n' "$name"; cat "$log"; failed=$((failed+1))
        fi
        count=$((count+1))
    done < <(declare -F)
    rm -f "$log"
    printf '%s: %d cases, %d failures\n' "$(basename "$0")" "$count" "$failed"
    [[ $failed == 0 && $count -gt 0 ]]
}
