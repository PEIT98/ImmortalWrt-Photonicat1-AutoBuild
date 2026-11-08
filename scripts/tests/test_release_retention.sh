#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
setup() {
    SCRIPT="$ROOT/scripts/release/prune-releases.sh"
    mkdir -p "$TEST_TMP/bin"
    export RETENTION_TEST_ROOT="$TEST_TMP"
    export GITHUB_REPOSITORY=PEIT98/ImmortalWrt-Photonicat1-AutoBuild
    export GITHUB_STEP_SUMMARY="$TEST_TMP/summary"
    cat > "$TEST_TMP/bin/gh" <<'GH'
#!/bin/sh
set -eu
case "$1" in
    api)
        [ "$#" = 5 ] && [ "$2" = --paginate ] &&
            [ "$3" = "repos/$GITHUB_REPOSITORY/releases?per_page=100" ] &&
            [ "$4" = --jq ] && [ "$5" = '.[]' ] || exit 90
        printf 'paginated releases\n' >> "$RETENTION_TEST_ROOT/api.log"
        [ ! -e "$RETENTION_TEST_ROOT/api-fail" ] || exit 1
        cat "$RETENTION_TEST_ROOT/releases.ndjson"
        ;;
    release)
        [ "$#" = 7 ] && [ "$2" = delete ] && [ "$4" = --repo ] &&
            [ "$5" = "$GITHUB_REPOSITORY" ] && [ "$6" = --yes ] &&
            [ "$7" = --cleanup-tag ] || exit 91
        printf '%s\n' "$3" >> "$RETENTION_TEST_ROOT/deleted"
        if [ -e "$RETENTION_TEST_ROOT/delete-fail" ]; then exit 1; fi
        ;;
    *) exit 92 ;;
esac
GH
    chmod +x "$TEST_TMP/bin/gh"
    export PATH="$TEST_TMP/bin:$PATH"
    fixture 8
    current=$(tag 8)
}
tag() { printf 'photonicat1-20261108-120000-%s\n' "$1"; }
fixture() {
    jq -nc --argjson total "$1" '
      range(1;$total+1) as $i |
      {id:$i, tag_name:("photonicat1-20261108-120000-"+($i|tostring)),
       draft:false, prerelease:($i%2==1), published_at:"2026-11-08T12:00:00Z"}
    ' > "$TEST_TMP/releases.ndjson"
}
test_keep_five_with_corresponding_tags() {
    printf '%s\n' '{"id":999,"tag_name":"other-project-v1","draft":false,"published_at":"2026-12-01T00:00:00Z"}' \
        '{"id":1000,"tag_name":"photonicat1-20261109-120000-1000","draft":true,"published_at":null}' >> "$TEST_TMP/releases.ndjson"
    ok bash "$SCRIPT" 5 "$current"
    assert_eq "$(printf '%s\n' "$(tag 3)" "$(tag 2)" "$(tag 1)")" "$(cat "$TEST_TMP/deleted")"
    assert_has "$GITHUB_STEP_SUMMARY" '实际保留：5 个'
    assert_has "$GITHUB_STEP_SUMMARY" '对应标签：3 个'
}
test_custom_retention_count() {
    ok bash "$SCRIPT" 2 "$current"
    assert_eq 6 "$(wc -l < "$TEST_TMP/deleted")"
    assert_not_has "$TEST_TMP/deleted" "$(tag 8)"
    assert_not_has "$TEST_TMP/deleted" "$(tag 7)"
}
test_fewer_releases_need_no_deletion() {
    fixture 3
    ok bash "$SCRIPT" 5 "$(tag 3)"
    assert_absent "$TEST_TMP/deleted"
    assert_has "$GITHUB_STEP_SUMMARY" '实际保留：3 个'
}
test_current_release_counts_toward_limit_and_is_preserved() {
    ok bash "$SCRIPT" 1 "$(tag 1)"
    assert_eq 7 "$(wc -l < "$TEST_TMP/deleted")"
    assert_not_has "$TEST_TMP/deleted" "$(tag 1)"
}
test_missing_current_release_prevents_deletion() {
    reject bash "$SCRIPT" 5 "$(tag 9999)"
    assert_absent "$TEST_TMP/deleted"
}
test_invalid_input_prevents_api_calls() {
    local keep
    for keep in 0 -1 1.5 '5; reboot' abc; do
        reject bash "$SCRIPT" "$keep" "$current"
        assert_absent "$TEST_TMP/api.log"
        assert_absent "$TEST_TMP/deleted"
    done
    reject bash "$SCRIPT" 5 invalid-tag
    assert_absent "$TEST_TMP/api.log"
}
test_api_failure_prevents_deletion() {
    touch "$TEST_TMP/api-fail"
    reject bash "$SCRIPT" 5 "$current"
    assert_absent "$TEST_TMP/deleted"
}
test_delete_failure_stops_later_deletions() {
    touch "$TEST_TMP/delete-fail"
    reject bash "$SCRIPT" 5 "$current"
    assert_eq "$(tag 3)" "$(cat "$TEST_TMP/deleted")"
}
test_more_than_one_hundred_releases() {
    fixture 105
    ok bash "$SCRIPT" 5 "$(tag 105)"
    assert_eq 100 "$(wc -l < "$TEST_TMP/deleted")"
    assert_eq "$(tag 100)" "$(head -n 1 "$TEST_TMP/deleted")"
    assert_eq "$(tag 1)" "$(tail -n 1 "$TEST_TMP/deleted")"
}
run_tests "$@"
