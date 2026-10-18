#!/usr/bin/env bash
# Fetch the current official stable Meta core for Photonicat1 before image assembly.
set -euo pipefail

overlay="${1:?usage: bundle-openclash-core.sh <immortalwrt/files>}"
test -d "$overlay"

repo='https://github.com/vernesong/OpenClash.git'
revision="$(git ls-remote "$repo" refs/heads/core | awk '$2 == "refs/heads/core" { print $1 }')"
[[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo '::error::OpenClash core branch revision unavailable' >&2; exit 1; }
raw="https://raw.githubusercontent.com/vernesong/OpenClash/$revision/master"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 --connect-timeout 20 --max-time 180 "$raw/meta/checksums.txt" -o "$tmp/checksums.txt"
curl -fsSL --retry 3 --connect-timeout 20 --max-time 60 "$raw/core_version" -o "$tmp/core_version"
curl -fsSL --retry 3 --connect-timeout 20 --max-time 300 "$raw/meta/clash-linux-arm64.tar.gz" -o "$tmp/clash-linux-arm64.tar.gz"

awk '$2 == "./clash-linux-arm64.tar.gz" && $1 ~ /^[0-9a-f]+$/ { print $1 "  clash-linux-arm64.tar.gz" }' \
  "$tmp/checksums.txt" > "$tmp/sha256sum.txt"
test "$(wc -l < "$tmp/sha256sum.txt")" -eq 1 || { echo '::error::OpenClash arm64 checksum missing or ambiguous' >&2; exit 1; }
(cd "$tmp" && sha256sum -c sha256sum.txt)

# The official OpenClash updater expects a single archive entry named clash.
test "$(tar -tzf "$tmp/clash-linux-arm64.tar.gz")" = 'clash' || {
  echo '::error::OpenClash core archive layout changed' >&2; exit 1;
}
tar --no-same-owner -xzf "$tmp/clash-linux-arm64.tar.gz" -C "$tmp" clash
test "$(readelf -h "$tmp/clash" | awk -F: '/Machine:/ {gsub(/^[[:space:]]+/, "", $2); print $2}')" = 'AArch64' || {
  echo '::error::OpenClash core is not an AArch64 ELF binary' >&2; exit 1;
}
version="$(head -n 1 "$tmp/core_version" | tr -d '\r')"
[[ "$version" =~ ^[A-Za-z0-9._+-]+$ ]] || { echo '::error::OpenClash core version invalid' >&2; exit 1; }

dest="$overlay/usr/libexec/photonicat/openclash"
mkdir -p "$dest"
install -m 0755 "$tmp/clash" "$dest/clash_meta"
printf 'Version: %s\nOpenClash core commit: %s\nArchive SHA256: %s\n' \
  "$version" "$revision" "$(cut -d ' ' -f 1 "$tmp/sha256sum.txt")" > "$dest/build-info"
test -x "$dest/clash_meta" && test -s "$dest/build-info"
echo "OpenClash Meta $version ($revision) bundled for linux-arm64"
