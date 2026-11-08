#!/bin/bash
source "$(dirname "$0")/common.sh"
setup() {
    package="$ROOT/packages/luci-app-online-upgrade/root"
    engine="$package/usr/libexec/swrt-upgrade"
    repo=PEIT98/ImmortalWrt-Photonicat1-AutoBuild
    root="$TEST_TMP/root"
    mkdir -p "$root"/{etc,proc,sbin,bin,tmp/sysinfo,fixtures}
    identity="$root/etc/photonicat-release.json"
    printf '{"repository":"%s","board":"ariaboard,photonicat","version":"photonicat1-20261101-120000-9"}\n' "$repo" > "$identity"
    board="$root/tmp/sysinfo/board_name"; printf 'ariaboard,photonicat\n' > "$board"
    mounts="$root/proc/mounts"; printf '/dev/root /rom squashfs ro 0 0\noverlay / overlay rw 0 0\n' > "$mounts"
    name=Pwrt-P1_2026110223.img.gz
    fixture="$root/fixtures"
    printf 'fixture image' | gzip -n > "$fixture/image"
    printf ' {"supported_devices":["ariaboard,photonicat"]} FWx0' >> "$fixture/image"
    sha=$(sha256sum "$fixture/image" | cut -d ' ' -f1); size=$(stat -c %s "$fixture/image")
    printf '%s  ./%s\n' "$sha" "$name" > "$fixture/sha256sums"
    jq -n --arg name "$name" --arg sha "$sha" --argjson size "$size" --arg base "https://github.com/$repo/releases/download/photonicat1-20261102-222244-55/" '{tag_name:"photonicat1-20261102-222244-55",draft:false,prerelease:false,body:"中文发布说明",published_at:"2026-10-24T00:00:00Z",assets:[{id:1,name:$name,size:$size,browser_download_url:($base+$name),digest:("sha256:"+$sha)},{id:2,name:"SHA256SUMS.txt",browser_download_url:($base+"SHA256SUMS.txt")}]}' > "$fixture/release.json"
    cp "$fixture/release.json" "$TEST_TMP/release.original"
    cp "$ROOT/scripts/tests/fixtures/mock-upgrade-curl.sh" "$root/bin/curl"
    cp "$ROOT/scripts/tests/fixtures/mock-uci-config.sh" "$root/bin/uci"
    mkdir -p "$root/etc/config"
    printf "config settings 'main'\n\toption source 'proxy'\n" > "$root/etc/config/swrt_upgrade"
    cp "$ROOT/scripts/tests/fixtures/mock-sysupgrade.sh" "$root/sbin/sysupgrade"
    cat > "$root/bin/ubus" <<'UBUS'
#!/bin/sh
if [ -f "$SWRT_UPGRADE_ROOT/invalid-metadata" ]; then
    printf '{"valid":false,"allow_backup":false}\n'
else
    printf '{"valid":true,"allow_backup":true}\n'
fi
UBUS
    chmod +x "$root/bin/"* "$root/sbin/sysupgrade"
    export SWRT_UPGRADE_ROOT="$root" SWRT_UPGRADE_SCRIPT="$engine" PATH="$root/bin:$PATH"
    worker="$root/tmp/swrt-upgrade"; state="$worker/state.json"; log="$root/sysupgrade.log"
}
engine_ok() {
    ok sh "$engine" "$1" <<<"${2:-}"; assert_json "$OUT" '.ok==true'
    if [[ $1 == check ]]; then
        wait_worker
        ok sh "$engine" status
        assert_json "$OUT" '.ok==true and (.state.phase=="available" or .state.phase=="current")'
    fi
}
engine_reject() {
    capture sh "$engine" "$1" <<<"${2:-}"
    if [[ $1 == check && $RC == 0 ]]; then
        wait_worker
        assert_json "$state" '.phase=="failed"'
    else
        [[ $RC != 0 ]] || fail "command unexpectedly succeeded: $1"
    fi
}
wait_worker() {
    local i
    for ((i=0;i<270;i++)); do
        if [[ -f $state ]] && jq -e '.phase=="ready" or .phase=="failed" or .phase=="available" or .phase=="current"' "$state" >/dev/null; then
            flock -w 3 "$worker/lock" true || fail 'worker lock timeout'
            return
        fi
        sleep 0.03
    done
    cat "$worker/worker.log" >&2 || true; fail 'worker timeout'
}
prepare() { engine_ok check; engine_ok download; wait_worker; assert_json "$state" '.phase=="ready"'; }
no_flash() { if [[ -e $log ]] && grep -Ev '^-T ' "$log"; then fail 'unexpected flash'; fi; }
test_identity_signature_and_acl() {
    ok sh "$package/usr/libexec/rpcd/luci.swrt_upgrade" list
    assert_json "$OUT" '(.install.keep|type)=="number" and (.set_source.source|type)=="string" and (.set_channel.channel|type)=="string"'
    ok sh "$ROOT/scripts/release/stamp-firmware.sh" "$TEST_TMP/stamp" photonicat1-20261102-222244-55 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    assert_json "$TEST_TMP/stamp/files/etc/photonicat-release.json" '.repository=="PEIT98/ImmortalWrt-Photonicat1-AutoBuild" and .board=="ariaboard,photonicat" and .version=="photonicat1-20261102-222244-55" and .commit=="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'
    local legacy="$TEST_TMP/stamp/files/etc/online-upgrade-device"
    ok sh -n "$legacy"
    assert_eq 'ariaboard,photonicat|photonicat1-20261102-222244-55|aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$(sh -c '. "$1"; printf "%s|%s|%s" "$DEVICE_BOARD" "$BUILD_TAG" "$BUILD_COMMIT"' sh "$legacy")"
    cp "$TEST_TMP/stamp/files/etc/photonicat-release.json" "$TEST_TMP/identity.before"
    cp "$legacy" "$TEST_TMP/legacy.before"
    for tag in 1.10 photonicat1-00001102-222244-55 photonicat1-20260230-222244-55 photonicat1-20261102-256144-55; do
        reject sh "$ROOT/scripts/release/stamp-firmware.sh" "$TEST_TMP/stamp" "$tag" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
        assert_same "$TEST_TMP/stamp/files/etc/photonicat-release.json" "$TEST_TMP/identity.before"
        assert_same "$legacy" "$TEST_TMP/legacy.before"
    done
    reject sh "$ROOT/scripts/release/stamp-firmware.sh" "$TEST_TMP/stamp" photonicat1-20261102-222244-55 invalid-commit
    assert_same "$TEST_TMP/stamp/files/etc/photonicat-release.json" "$TEST_TMP/identity.before"
    assert_same "$legacy" "$TEST_TMP/legacy.before"
    assert_json "$package/usr/share/rpcd/acl.d/luci-app-online-upgrade.json" '.["luci-app-online-upgrade"]|.read=={ubus:{"luci.swrt_upgrade":["status"]}} and (.write.ubus["luci.swrt_upgrade"]|sort)==(["check","download","install","set_source","set_channel"]|sort) and (.write|has("file")|not)'
    assert_has "$package/etc/config/swrt_upgrade" "option source 'github'"
    assert_has "$package/../Makefile" 'Package/luci-app-online-upgrade/conffiles'
    assert_has "$package/../Makefile" /etc/config/swrt_upgrade
}
test_identity_generation_failure_preserves_both_files() {
    local stamp="$TEST_TMP/stamp" script="$ROOT/scripts/release/stamp-firmware.sh"
    ok sh "$script" "$stamp" photonicat1-20261102-222244-55 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    cp "$stamp/files/etc/photonicat-release.json" "$TEST_TMP/identity.before"
    cp "$stamp/files/etc/online-upgrade-device" "$TEST_TMP/legacy.before"
    mkdir "$TEST_TMP/stamp-bin"
    printf '#!/bin/sh\nprintf "incomplete JSON\\n"\nexit 1\n' > "$TEST_TMP/stamp-bin/jq"
    chmod +x "$TEST_TMP/stamp-bin/jq"
    reject env PATH="$TEST_TMP/stamp-bin:$PATH" sh "$script" "$stamp" photonicat1-20261103-222244-56 bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
    assert_same "$stamp/files/etc/photonicat-release.json" "$TEST_TMP/identity.before"
    assert_same "$stamp/files/etc/online-upgrade-device" "$TEST_TMP/legacy.before"
    assert_eq 2 "$(find "$stamp/files/etc" -mindepth 1 -maxdepth 1 | wc -l)"
}
test_numeric_version_and_no_flash() {
    engine_ok check; assert_json "$OUT" '.current=="photonicat1-20261101-120000-9" and .release.version=="photonicat1-20261102-222244-55"'
    engine_ok download; wait_worker; assert_json "$state" '.phase=="ready"'
    engine_ok status; assert_json "$OUT" ".release.sha256==\"$sha\" and .downloaded_bytes==$size"; no_flash
}
test_check_returns_before_network_and_holds_lock() {
    touch "$root/api-block"
    ok sh "$engine" check
    assert_json "$OUT" '.ok==true'
    engine_ok status; assert_json "$OUT" '.state.phase=="checking" and .release==null'
    engine_reject check
    engine_reject set-source '{"source":"github"}'
    assert_absent "$log"
    rm "$root/api-block"
    wait_worker
    engine_ok status; assert_json "$OUT" '.state.phase=="available"'
    assert_absent "$log"
}
test_check_retries_transient_network_on_selected_source() {
    local source
    for source in proxy github; do
        engine_ok set-source "{\"source\":\"$source\"}"
        : > "$root/curl.log"
        touch "$root/api-fail-once"
        engine_ok check
        assert_eq 2 "$(wc -l < "$root/curl.log")"
        assert_eq 1 "$(sort -u "$root/curl.log" | wc -l)"
        assert_json "$OUT" ".source==\"$source\" and .release.version==\"photonicat1-20261102-222244-55\""
        if [[ $source == proxy ]]; then assert_has "$root/curl.log" 'https://gh-proxy.com/https://api.github.com/';
        else assert_not_has "$root/curl.log" 'gh-proxy.com'; fi
        assert_absent "$log"
    done
}
test_check_retries_invalid_proxy_response() {
    touch "$root/api-html-once"
    engine_ok check
    assert_eq 2 "$(wc -l < "$root/curl.log")"
    assert_has "$worker/network.log" 'Invalid or incomplete firmware release response'
    assert_json "$worker/api.json" '.tag_name=="photonicat1-20261102-222244-55"'
    assert_absent "$log"
}
test_check_retries_empty_release_list() {
    touch "$root/api-empty-once"
    engine_ok check
    assert_eq 2 "$(wc -l < "$root/curl.log")"
    assert_json "$OUT" '.state.phase=="available" and .release.version=="photonicat1-20261102-222244-55"'
    assert_absent "$log"
}
test_check_retries_incomplete_release() {
    touch "$root/api-incomplete-once"
    engine_ok check
    assert_eq 2 "$(wc -l < "$root/curl.log")"
    assert_json "$OUT" '.state.phase=="available" and .release.version=="photonicat1-20261102-222244-55"'
    assert_absent "$log"
}
test_download_retries_empty_release_revalidation() {
    engine_ok check
    touch "$root/api-empty-once"
    engine_ok download
    wait_worker
    assert_json "$state" '.phase=="ready"'
    assert_eq 5 "$(wc -l < "$root/curl.log")"
    no_flash
}
test_prerelease_and_stable() {
    update_json "$fixture/release.json" '.prerelease=true'
    engine_ok check; assert_json "$OUT" '.channel=="prerelease" and .release.prerelease'
    engine_ok set-channel '{"channel":"stable"}'; assert_json "$OUT" '.release==null'
    engine_reject check; update_json "$fixture/release.json" '.prerelease=false'
    engine_ok check; assert_json "$OUT" '.state.phase=="available"'
    [[ $(tail -n1 "$root/curl.log") == */latest ]] || fail 'stable endpoint changed'
}
test_release_run_numeric_sort() {
    jq --arg repo "$repo" '[9,10] as $runs|. as $base|[$runs[]|. as $run|$base|.tag_name=("photonicat1-20261102-222244-"+($run|tostring))|.prerelease=true|.tag_name as $tag|.assets|=map(.browser_download_url=("https://github.com/"+$repo+"/releases/download/"+$tag+"/"+.name))]|reverse' "$TEST_TMP/release.original" > "$fixture/release.json"
    engine_ok check; assert_json "$OUT" '.release.tag=="photonicat1-20261102-222244-10"'
}
test_legacy_identity_is_data() {
    rm "$identity"; mkdir -p "$root/rom/etc"
    printf "BUILD_TAG='photonicat1-20261101-120000-9'\n" > "$root/rom/etc/online-upgrade-device"
    engine_ok check; assert_json "$OUT" '.current=="photonicat1-20261101-120000-9"'
    printf '%s\n' "BUILD_TAG='\$(touch /tmp/should-never-run)'" > "$root/rom/etc/online-upgrade-device"
    engine_reject check
}
test_source_and_channel_saved() {
    engine_ok status; assert_json "$OUT" '.keep_default'
    engine_ok set-source '{"source":"github"}'
    engine_ok set-channel '{"channel":"stable"}'; assert_json "$OUT" '.source=="github"'
    engine_ok status; assert_json "$OUT" '.channel=="stable"'
    engine_ok set-source '{"source":"proxy"}'; engine_ok status; assert_json "$OUT" '.channel=="stable"'
}
test_missing_config_defaults_to_github() {
    rm "$root/etc/config/swrt_upgrade"
    engine_ok status; assert_json "$OUT" '.source=="github"'
}
test_real_release_schema() {
    cp "$ROOT/scripts/tests/fixtures/photonicat-release.json" "$fixture/release.json"
    engine_ok check; assert_json "$OUT" '.release.tag=="photonicat1-20261102-222244-55" and .release.prerelease and (.release.name|contains("ariaboard_photonicat-squashfs-sysupgrade_"))'
}
test_historical_filenames_still_download_and_validate() {
    local prefix legacy
    for prefix in photonicat-wrt immortalwrt pwrt; do
        legacy="$prefix-25.12-snapshot-r0-3682a14d-rockchip-armv8-ariaboard_photonicat-squashfs-sysupgrade_2026110223.img.gz"
        jq --arg name "$legacy" '.assets[0].name=$name | .assets[0].browser_download_url=(.assets[0].browser_download_url|sub("[^/]+$";$name))' "$TEST_TMP/release.original" > "$fixture/release.json"
        printf '%s  ./%s\n' "$sha" "$legacy" > "$fixture/sha256sums"
        prepare; no_flash
    done
}
test_wrong_short_names_and_duplicate_images_rejected() {
    local bad
    for bad in Pwrt-P2_2026110223.img.gz Pwrt-P1_202611022.img.gz Pwrt-P1_2026110223-ext4.img.gz Pwrt-P1_2026110223.img.gz.bak ../Pwrt-P1_2026110223.img.gz; do
        jq --arg name "$bad" '.assets[0].name=$name | .assets[0].browser_download_url=(.assets[0].browser_download_url|sub("[^/]+$";$name))' "$TEST_TMP/release.original" > "$fixture/release.json"
        engine_reject check; assert_absent "$log"
    done
    jq '.assets += [.assets[0]]' "$TEST_TMP/release.original" > "$fixture/release.json"
    engine_reject check; assert_absent "$log"
}
test_proxy_and_canonical_urls() {
    prepare; assert_eq 4 "$(wc -l < "$root/curl.log")"
    if grep -v '^https://gh-proxy.com/https://' "$root/curl.log"; then fail 'unproxied request'; fi
    assert_has "$root/curl.log" api.github.com
    [[ $(sed -n 3p "$root/curl.log") == */SHA256SUMS.txt && $(sed -n 4p "$root/curl.log") == */"$name" ]]
    engine_ok status; assert_json "$OUT" '.source=="proxy" and .release.source=="proxy" and (.release.url|startswith("https://github.com/"))'
}
test_switch_source_invalidates_ready() {
    prepare
    engine_ok set-source '{"source":"github"}'
    assert_json "$OUT" '.source=="github" and .state.phase=="idle" and .release==null'; assert_absent "$worker/firmware.img.gz"
    engine_ok status; assert_json "$OUT" '.source=="github"'
    : > "$root/curl.log"; prepare; assert_eq 4 "$(wc -l < "$root/curl.log")"
    if grep -Ev '^https://(api.github.com|github.com)/' "$root/curl.log"; then fail 'wrong GitHub request'; fi
}
test_invalid_source_preserves_ready() {
    prepare
    for value in '"https://example.com"' '"proxy; reboot"' '""' null '[]'; do
        engine_reject set-source "{\"source\":$value}"
        engine_ok status; assert_json "$OUT" '.state.phase=="ready"'; assert_file "$worker/firmware.img.gz"
    done
}
test_same_source_and_commit_failure() {
    prepare; engine_ok set-source '{"source":"proxy"}'; assert_json "$OUT" '.state.phase=="ready"'
    touch "$root/uci-fail"; engine_reject set-source '{"source":"github"}'
    engine_ok status; assert_json "$OUT" '.source=="proxy" and .state.phase=="ready"'
}
test_external_source_change_reverified() {
    prepare; mkdir -p "$root/etc/config"; printf "config settings 'main'\n\toption source 'github'\n" > "$root/etc/config/swrt_upgrade"
    engine_ok install "{\"keep\":0,\"sha256\":\"$sha\"}"; wait_worker
    assert_json "$state" '.phase=="failed" and (.message|contains("更新源已变化"))'; no_flash
}
test_installing_source_locked() {
    engine_ok check; printf '{"phase":"installing"}\n' > "$state"
    engine_reject set-source '{"source":"github"}'; engine_ok status; assert_json "$OUT" '.source=="proxy"'
}
test_unknown_board_and_identity() {
    for values in 'ariaboard,photonicat2 photonicat1-20261101-120000-9' 'ariaboard,photonicat empty'; do
        read -r b v <<< "$values"; [[ $v != empty ]] || v=
        printf '%s\n' "$b" > "$board"; update_json "$identity" ".version=\"$v\""
        engine_reject check; assert_absent "$root/curl.log"
    done
}
test_rom_identity_priority() {
    mkdir -p "$root/rom/etc"; cp "$identity" "$root/rom/etc/photonicat-release.json"; printf '{}\n' > "$identity"
    engine_ok check; assert_json "$OUT" '.current=="photonicat1-20261101-120000-9"'
}
test_filesystem_switch_rejected() {
    printf '/dev/root / ext4 rw 0 0\n' > "$mounts"; engine_reject check; assert_absent "$log"
}
test_release_validation() {
    for expr in '.draft=true' '.assets|=.[0:1]' '.assets[0].browser_download_url="https://example.com/image.img.gz"'; do
        cp "$TEST_TMP/release.original" "$fixture/release.json"; update_json "$fixture/release.json" "$expr"; engine_reject check
    done
}
test_same_or_older_release() {
    for version in photonicat1-20261102-222244-55 photonicat1-20261103-000000-56; do
        update_json "$identity" ".version=\"$version\""; engine_ok check; assert_json "$OUT" '.state.phase=="current"'; engine_reject download
    done
}
corrupt() { head -c "$size" /dev/zero | tr '\000' x > "$1"; }
test_corrupt_download() {
    engine_ok check; corrupt "$fixture/image"; engine_ok download; wait_worker
    assert_json "$state" '.phase=="failed"'; assert_absent "$worker/firmware.img.gz"; assert_absent "$log"
}
test_partition_and_platform_validation() {
    for flag in partition-change incompatible invalid-metadata; do
        touch "$root/$flag"; engine_ok check; engine_ok download; wait_worker; assert_json "$state" '.phase=="failed"'; rm "$root/$flag"
    done
}
test_asset_replacement() {
    engine_ok check; update_json "$fixture/release.json" '.assets[0].id=99'; engine_ok download; wait_worker
    assert_json "$state" '.phase=="failed"'; assert_absent "$log"
}
test_duplicate_checksum_and_network_error() {
    engine_ok check; cat "$fixture/sha256sums" "$fixture/sha256sums" > "$TEST_TMP/sums"; cp "$TEST_TMP/sums" "$fixture/sha256sums"
    engine_ok download; wait_worker; assert_json "$state" '.phase=="failed"'; assert_absent "$log"
    : > "$root/curl.log"
    touch "$root/network-fail"; engine_reject check; engine_ok status
    assert_json "$OUT" '.state.phase=="failed" and (.state.message|contains("3次"))'
    assert_eq 3 "$(wc -l < "$root/curl.log")"
    assert_absent "$worker/api.json"
}
test_ready_tampering() {
    prepare; corrupt "$worker/firmware.img.gz"; engine_ok install "{\"keep\":0,\"sha256\":\"$sha\"}"; wait_worker
    assert_json "$state" '.phase=="failed"'; no_flash
}
test_confirmed_digest_and_no_force() {
    prepare; engine_reject install '{"keep":0,"sha256":"0000000000000000000000000000000000000000000000000000000000000000"}'
    prepare; engine_ok install "{\"keep\":0,\"sha256\":\"$sha\"}"; wait_worker
    assert_json "$state" '.phase=="failed"'; grep -q '^-n ' "$log"
    assert_not_has "$log" --force; assert_not_has "$log" '-F '; assert_file "$worker/firmware.img.gz"
}
test_stage2_handoff_retains_firmware() {
    prepare; touch "$root/handoff-signal"; engine_ok install "{\"keep\":0,\"sha256\":\"$sha\"}"
    for ((i=0;i<270;i++)); do [[ ! -f $root/handoff-pid ]] || break; sleep 0.03; done
    assert_file "$root/handoff-pid"; flock -w 3 "$worker/lock" true
    assert_eq "$sha" "$(sha256sum "$worker/firmware.img.gz" | cut -d ' ' -f1)"
    assert_json "$state" '.phase=="installing"'; assert_eq 1 "$(grep -c '^-n ' "$log")"
}
test_sysupgrade_rejection_retains_firmware() {
    for keep in 0 1; do
        prepare; touch "$root/upgrade-reject"; engine_ok install "{\"keep\":$keep,\"sha256\":\"$sha\"}"; wait_worker
        assert_json "$state" '.phase=="failed" and (.message|contains("拒绝或中止请求"))'
        assert_eq "$sha" "$(sha256sum "$worker/firmware.img.gz" | cut -d ' ' -f1)"; rm "$root/upgrade-reject"
    done
}
test_concurrent_and_stale_worker() {
    engine_ok check; touch "$root/download-delay"; engine_ok download
    engine_reject download; engine_reject set-source '{"source":"github"}'
    engine_ok status; assert_json "$OUT" '.source=="proxy"'
    wait_worker; assert_json "$state" '.phase=="ready"'
    printf '{"phase":"downloading"}\n' > "$state"; engine_ok status; assert_json "$OUT" '.state.phase=="failed"'
}
run_tests "$@"
