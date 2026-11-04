#!/usr/bin/env bash
# Bundle an isolated E108 firmware set; retain all upstream default firmware.
set -euo pipefail

src="${1:?usage: bundle-nfa765-e108.sh <immortalwrt>}"
project="$(cd "$(dirname "$0")/../.." && pwd)"
data="$project/firmware/nfa765-e108"
revision=273e26348fbd4c14320f6789e999b3211e696690
base="https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware/+/$revision/ath11k/WCN6855/hw2.0/nfa765"
patch_name=999-photonicat-nfa765-e108-firmware.patch
patch_src="$project/patches/ath11k/$patch_name"
patch_dst="$src/package/kernel/mac80211/patches/ath11k/$patch_name"
recipe="$src/package/firmware/linux-firmware/qca_ath11k.mk"

fail() { printf '::error::%s\n' "$*" >&2; exit 1; }
test -f "$recipe" && test -f "$src/package/kernel/mac80211/Makefile" || fail '缺少官方 WCN6855 固件或 mac80211 源码'
grep -Fxq 'define Package/ath11k-firmware-wcn6855/install' "$recipe" || fail '上游 WCN6855 安装定义已变化'
grep -Fxq $'\t$(LN) ./hw2.0 $(1)/lib/firmware/ath11k/WCN6855/hw2.1' "$recipe" || fail '上游 hw2.1 目录结构已变化，请先核对加载路径'
test -s "$patch_src" && test -s "$data/LICENSE.QualcommAtheros_ath10k" || fail '缺少 E108 补丁或固件许可'
if [[ -e "$patch_dst" || -L "$patch_dst" ]]; then
    [[ ! -L "$patch_dst" ]] && cmp -s "$patch_src" "$patch_dst" || fail '已有同名 E108 驱动补丁内容不同'
fi

work="$(mktemp -d)"
stage=
trap 'rm -rf "$work"; if [[ -n "$stage" ]]; then rm -rf "$stage"; fi' EXIT
mkdir "$work/payload"
gzip -dc "$data/board-2.bin.gz" > "$work/payload/board-2.bin"
check() { [[ "$(sha256sum "$1" | cut -d ' ' -f 1)" == "$2" ]]; }
board_hash="$(awk '$2=="board-2.bin" {print $1}' "$data/SHA256SUMS")"
check "$work/payload/board-2.bin" "$board_hash" || fail '内置 E108 板卡文件校验失败'

cache="$src/dl/photonicat-nfa765-e108-$revision"
mkdir -p "$cache"
for name in amss.bin m3.bin Notice.txt; do
    expected="$(awk -v name="$name" '$2==name {print $1}' "$data/SHA256SUMS")"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fail "缺少 $name 校验值"
    if [[ -f "$cache/$name" ]] && check "$cache/$name" "$expected"; then
        cp "$cache/$name" "$work/payload/$name"
    else
        curl -fsSL --retry 3 --connect-timeout 20 --max-time 180 "$base/$name?format=TEXT" -o "$work/$name.b64"
        base64 -d "$work/$name.b64" > "$work/payload/$name"
        check "$work/payload/$name" "$expected" || fail "上游 $name 校验失败"
        install -m 0644 "$work/payload/$name" "$cache/.$name.new"
        mv -f "$cache/.$name.new" "$cache/$name"
    fi
done
(cd "$work/payload" && sha256sum -c "$data/SHA256SUMS")
cp "$data/LICENSE.QualcommAtheros_ath10k" "$work/payload/"
cp "$data/SHA256SUMS" "$work/payload/"
printf 'PCI: 17cb:1103 / 105b:e108; WCN6855 hw2.1 only\nLinux-firmware commit: %s\nFirmware: WLAN.HSP.1.1-04866.5-QCAHSPSWPL_V1_V2_SILICONZ_IOE-1\n' "$revision" > "$work/payload/build-info"

# hw2.1 -> hw2.0 is intentionally retained. Only the private subdirectory is added.
dest="$src/files/lib/firmware/ath11k/WCN6855/hw2.0/nfa765-e108"
if [[ -e "$dest" || -L "$dest" ]]; then
    [[ -d "$dest" && ! -L "$dest" ]] && diff -qr "$work/payload" "$dest" >/dev/null || fail '已有 E108 固件目录内容不同，停止覆盖'
else
    mkdir -p "${dest%/*}"
    stage="$(mktemp -d "${dest%/*}/.nfa765-e108.XXXXXX")"
    install -m 0644 "$work/payload/"* "$stage/"
    mv "$stage" "$dest"
    stage=
fi
mkdir -p "${patch_dst%/*}"
if [[ ! -e "$patch_dst" ]]; then install -m 0644 "$patch_src" "$patch_dst"; fi
printf '%s\n' 'NFA765 E108 专用固件已内置，普通卡和 hw2.0/hw2.1 默认文件保留。'
