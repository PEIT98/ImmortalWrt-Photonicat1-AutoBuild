#!/bin/bash
source "$(dirname "$0")/common.sh"

setup() {
    package="$ROOT/packages/luci-app-aurora-upgrade/root"
    engine="$package/usr/libexec/aurora-update"
    export AURORA_UPDATE_ROOT="$TEST_TMP/device"
    mkdir -p "$AURORA_UPDATE_ROOT/etc/config" "$AURORA_UPDATE_ROOT/bin" "$AURORA_UPDATE_ROOT/fixtures"
    cp "$package/etc/config/aurora_update" "$AURORA_UPDATE_ROOT/etc/config/aurora_update"
    cp "$ROOT/scripts/tests/fixtures/mock-uci-config.sh" "$AURORA_UPDATE_ROOT/bin/uci"
    cat > "$AURORA_UPDATE_ROOT/bin/curl" <<'CURL'
#!/bin/sh
set -eu
while [ "$#" -gt 1 ]; do
    case "$1" in -o) target=$2; shift 2 ;; *) shift ;; esac
done
url=$1
printf '%s\n' "$url" >> "$AURORA_UPDATE_ROOT/urls"
case "$url" in
    */repos/eamonxg/luci-theme-aurora/releases/latest) cp "$AURORA_UPDATE_ROOT/fixtures/theme.json" "$target" ;;
    */repos/eamonxg/luci-app-aurora-config/releases/latest) cp "$AURORA_UPDATE_ROOT/fixtures/config.json" "$target" ;;
    */luci-theme-aurora-1.4.0-r20260920.apk|*/luci-app-aurora-config-1.2.5-r20260920.apk)
        if [ -e "$AURORA_UPDATE_ROOT/corrupt" ]; then printf 'bad file' > "$target";
        else printf 'verified apk' > "$target"; fi ;;
    *) exit 1 ;;
esac
CURL
    cat > "$AURORA_UPDATE_ROOT/bin/apk" <<'APK'
#!/bin/sh
set -eu
case "$1" in
    list)
        pkg=$3
        [ -f "$AURORA_UPDATE_ROOT/$pkg.installed" ] || exit 0
        printf '%s-%s aarch64_generic [installed]\n' "$pkg" "$(cat "$AURORA_UPDATE_ROOT/$pkg.installed")" ;;
    version)
        [ "$2" = -t ] || exit 1
        if [ "$3" = "$4" ]; then printf '=\n';
        elif [ "$(printf '%s\n%s\n' "$3" "$4" | sort -V | head -1)" = "$3" ]; then printf '<\n';
        else printf '>\n'; fi ;;
    add)
        [ "$2" = --allow-untrusted ] || exit 1
        pkg=$(basename "$3" .apk)
        [ "$pkg" = aurora ] || exit 1
        # This mock stands in for the selected release, not a real APK parser.
        printf '1.4.0-r20260920\n' > "$AURORA_UPDATE_ROOT/luci-theme-aurora.installed" ;;
    *) exit 1 ;;
esac
APK
    chmod +x "$AURORA_UPDATE_ROOT/bin/"*
    export PATH="$AURORA_UPDATE_ROOT/bin:$PATH"
    printf '1.3.0-r1\n' > "$AURORA_UPDATE_ROOT/luci-theme-aurora.installed"
    printf '1.2.5-r20260920\n' > "$AURORA_UPDATE_ROOT/luci-app-aurora-config.installed"
    sha=$(printf 'verified apk' | sha256sum | cut -d ' ' -f1)
    size=$(printf 'verified apk' | wc -c)
    jq -n --arg sha "$sha" --argjson size "$size" '
      {tag_name:"v1.4.0",draft:false,prerelease:false,assets:[
       {name:"luci-theme-aurora-1.4.0-r20260920.apk",size:$size,digest:("sha256:"+$sha),
        browser_download_url:"https://github.com/eamonxg/luci-theme-aurora/releases/download/v1.4.0/luci-theme-aurora-1.4.0-r20260920.apk"}]}' > "$AURORA_UPDATE_ROOT/fixtures/theme.json"
    jq -n --arg sha "$sha" --argjson size "$size" '
      {tag_name:"v1.2.5",draft:false,prerelease:false,assets:[
       {name:"luci-app-aurora-config-1.2.5-r20260920.apk",size:$size,digest:("sha256:"+$sha),
        browser_download_url:"https://github.com/eamonxg/luci-app-aurora-config/releases/download/v1.2.5/luci-app-aurora-config-1.2.5-r20260920.apk"}]}' > "$AURORA_UPDATE_ROOT/fixtures/config.json"
}

engine_ok() { ok sh "$engine" "$1" <<<"${2:-}"; assert_json "$OUT" '.ok==true'; }
engine_reject() { reject sh "$engine" "$1" <<<"${2:-}"; assert_json "$OUT" '.ok==false'; }

test_default_proxy_check_and_install() {
    engine_ok check
    assert_json "$OUT" '.releases.packages["luci-theme-aurora"].version=="1.4.0-r20260920" and .upgradeable["luci-theme-aurora"] and (.upgradeable["luci-app-aurora-config"]|not)'
    assert_eq 2 "$(wc -l < "$AURORA_UPDATE_ROOT/urls")"
    if grep -v '^https://gh-proxy.com/https://api.github.com/' "$AURORA_UPDATE_ROOT/urls"; then fail 'check bypassed proxy'; fi
    engine_ok install '{"package":"luci-theme-aurora"}'
    assert_eq '1.4.0-r20260920' "$(cat "$AURORA_UPDATE_ROOT/luci-theme-aurora.installed")"
    assert_has "$AURORA_UPDATE_ROOT/urls" 'https://gh-proxy.com/https://github.com/eamonxg/luci-theme-aurora/releases/download/'
    assert_absent "$AURORA_UPDATE_ROOT/tmp/aurora-update/releases.json"
}

test_switch_to_github_and_recheck() {
    engine_ok check
    engine_ok set_source '{"source":"github"}'
    assert_absent "$AURORA_UPDATE_ROOT/tmp/aurora-update/releases.json"
    engine_reject install '{"package":"luci-theme-aurora"}'
    : > "$AURORA_UPDATE_ROOT/urls"
    engine_ok check
    if grep -Ev '^https://api.github.com/' "$AURORA_UPDATE_ROOT/urls"; then fail 'check used wrong host'; fi
    engine_ok install '{"package":"luci-theme-aurora"}'
    assert_has "$AURORA_UPDATE_ROOT/urls" 'https://github.com/eamonxg/luci-theme-aurora/releases/download/'
}

test_untrusted_or_broken_asset_never_installs() {
    update_json "$AURORA_UPDATE_ROOT/fixtures/theme.json" '.assets[0].browser_download_url="https://example.com/untrusted.apk"'
    engine_reject check
    assert_absent "$AURORA_UPDATE_ROOT/tmp/aurora-update/releases.json"
    update_json "$AURORA_UPDATE_ROOT/fixtures/theme.json" '.assets[0].browser_download_url="https://github.com/eamonxg/luci-theme-aurora/releases/download/v1.4.0/luci-theme-aurora-1.4.0-r20260920.apk"'
    engine_ok check
    touch "$AURORA_UPDATE_ROOT/corrupt"
    engine_reject install '{"package":"luci-theme-aurora"}'
    assert_eq '1.3.0-r1' "$(cat "$AURORA_UPDATE_ROOT/luci-theme-aurora.installed")"
}

test_no_downgrade_and_invalid_input() {
    engine_ok check
    engine_reject install '{"package":"luci-app-aurora-config"}'
    printf '2.0.0-r1\n' > "$AURORA_UPDATE_ROOT/luci-theme-aurora.installed"
    engine_reject install '{"package":"luci-theme-aurora"}'
    engine_reject install '{"package":"other"}'
    engine_reject set_source '{"source":"http://example.com/"}'
    engine_ok status
    assert_json "$OUT" '.source=="proxy" and .releases.source=="proxy" and (.upgradeable["luci-theme-aurora"]|not)'
}

test_acl_and_package_registration() {
    ok sh "$package/usr/libexec/rpcd/luci.aurora_update" list
    assert_json "$OUT" 'has("check") and has("install") and has("set_source")'
    assert_json "$package/usr/share/rpcd/acl.d/luci-app-aurora-upgrade.json" '."luci-app-aurora-upgrade".write.ubus."luci.aurora_update"|sort==["check","install","set_source"]'
    assert_has "$ROOT/photonicat1.config" 'CONFIG_PACKAGE_luci-app-aurora-upgrade=y'
    assert_has "$ROOT/scripts/build/prepare.sh" 'AURORA_UPGRADE_DST'
}

run_tests
