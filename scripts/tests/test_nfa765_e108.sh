#!/usr/bin/env bash
# Exercise the real backports function and firmware packaging without a kernel build.
set -euo pipefail
project="$(cd "$(dirname "$0")/../.." && pwd)"
src="$(cd "${1:?usage: test_nfa765_e108.sh <prepared-immortalwrt>}" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
payload="$src/files/lib/firmware/ath11k/WCN6855/hw2.0/nfa765-e108"
patch_name=999-photonicat-nfa765-e108-firmware.patch
patch_file="$src/package/kernel/mac80211/patches/ath11k/$patch_name"
recipe="$src/package/firmware/linux-firmware/qca_ath11k.mk"
cp "$recipe" "$work/recipe.before"
(cd "$payload" && sha256sum -c "$project/firmware/nfa765-e108/SHA256SUMS")
cmp "$patch_file" "$project/patches/ath11k/$patch_name"
grep -aFq 'subsystem-vendor=105b,subsystem-device=e108,qmi-chip-id=2,qmi-board-id=255' "$payload/board-2.bin"
grep -aFq 'subsystem-vendor=105b,subsystem-device=e108,qmi-chip-id=18,qmi-board-id=255' "$payload/board-2.bin"
test -s "$payload/Notice.txt" && test -s "$payload/LICENSE.QualcommAtheros_ath10k"
bash "$project/scripts/build/bundle-nfa765-e108.sh" "$src"
cmp "$recipe" "$work/recipe.before"
printf '%s\n' 'PASS verified payload, E108 board IDs and idempotent bundling'

normal="$work/root/lib/firmware/ath11k/WCN6855"
mkdir -p "$normal/hw2.0"
for name in amss.bin m3.bin board-2.bin regdb.bin; do
    printf 'original %s\n' "$name" > "$normal/hw2.0/$name"
done
(cd "$normal/hw2.0" && sha256sum ./*.bin) > "$work/normal.sha256"
ln -s ./hw2.0 "$normal/hw2.1"
cp -a "$payload" "$normal/hw2.0/"
(cd "$normal/hw2.0" && sha256sum -c "$work/normal.sha256")
test -L "$normal/hw2.1" && test "$(readlink "$normal/hw2.1")" = ./hw2.0
(cd "$normal/hw2.1/nfa765-e108" && sha256sum -c "$project/firmware/nfa765-e108/SHA256SUMS")
printf '%s\n' 'PASS ordinary firmware and hw2.1 symlink preserved'

version="$(sed -n 's/^PKG_VERSION:=//p' "$src/package/kernel/mac80211/Makefile")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail 'Unexpected backports version'
archive="$src/dl/backports-$version.tar.zst"
expected="$(sed -n 's/^PKG_HASH:=//p' "$src/package/kernel/mac80211/Makefile")"
[[ "$(sha256sum "$archive" | cut -d ' ' -f 1)" == "$expected" ]] || fail 'Backports archive checksum mismatch'
mkdir "$work/backports"
tar -xf "$archive" -C "$work/backports" --strip-components=1 "backports-$version/drivers/net/wireless/ath/ath11k/core.h"
patch --batch --fuzz=0 -d "$work/backports" -p1 < "$patch_file"
cat > "$work/paths.c" <<'C'
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define ATH11K_FW_DIR "ath11k"
enum { ATH11K_HW_WCN6855_HW20, ATH11K_HW_WCN6855_HW21, OTHER_CHIP };
struct device { void *of_node; };
struct ath11k_base {
    int hw_rev;
    struct device *dev;
    struct { unsigned vendor, device, subsystem_vendor, subsystem_device; } id;
    struct { struct { const char *dir; } fw; } hw_params;
};
static const char *dt_override, *usecase;
static void of_property_read_string(void *node, const char *key, const char **value)
{ (void)node; (void)key; *value = dt_override; }
static const char *ath11k_core_get_usecase_firmware(struct ath11k_base *ab)
{ (void)ab; return usecase; }
C
sed -n '/^static inline void ath11k_core_create_firmware_path(/,/^}/p' "$work/backports/drivers/net/wireless/ath/ath11k/core.h" >> "$work/paths.c"
cat >> "$work/paths.c" <<'C'
static void expect(struct ath11k_base *ab, const char *file, const char *path)
{
    char result[256];
    ath11k_core_create_firmware_path(ab, file, result, sizeof(result));
    if (strcmp(result, path)) { fprintf(stderr, "%s != %s\n", result, path); assert(0); }
}
int main(void)
{
    struct device dev = {0};
    struct ath11k_base ab = { .hw_rev = ATH11K_HW_WCN6855_HW21, .dev = &dev,
        .id = {0x17cb, 0x1103, 0x105b, 0xe108}, .hw_params.fw.dir = "WCN6855/hw2.1" };
    const char *files[] = {"amss.bin", "m3.bin", "board-2.bin", "firmware-2.bin"};
    char path[256];
    for (unsigned i = 0; i < sizeof(files)/sizeof(files[0]); i++) {
        snprintf(path, sizeof(path), "ath11k/WCN6855/hw2.1/nfa765-e108/%s", files[i]);
        expect(&ab, files[i], path);
    }
    expect(&ab, "regdb.bin", "ath11k/WCN6855/hw2.1/regdb.bin");
    expect(&ab, "board.bin", "ath11k/WCN6855/hw2.1/board.bin");
    ab.id.subsystem_device = 0x0108;
    expect(&ab, "amss.bin", "ath11k/WCN6855/hw2.1/amss.bin");
    expect(&ab, "board-2.bin", "ath11k/WCN6855/hw2.1/board-2.bin");
    usecase = "nfa765";
    expect(&ab, "amss.bin", "ath11k/WCN6855/hw2.1/nfa765/amss.bin");
    expect(&ab, "board-2.bin", "ath11k/WCN6855/hw2.1/board-2.bin");
    usecase = NULL;
    ab.id.subsystem_device = 0xe108;
    ab.id.subsystem_vendor = 0x17cb;
    expect(&ab, "m3.bin", "ath11k/WCN6855/hw2.1/m3.bin");
    ab.id.subsystem_vendor = 0x105b;
    ab.id.device = 0x1107;
    expect(&ab, "board-2.bin", "ath11k/WCN6855/hw2.1/board-2.bin");
    ab.id.device = 0x1103;
    ab.id.vendor = 0x168c;
    expect(&ab, "amss.bin", "ath11k/WCN6855/hw2.1/amss.bin");
    ab.id.vendor = 0x17cb;
    ab.hw_rev = ATH11K_HW_WCN6855_HW20;
    ab.hw_params.fw.dir = "WCN6855/hw2.0";
    expect(&ab, "amss.bin", "ath11k/WCN6855/hw2.0/amss.bin");
    ab.hw_rev = OTHER_CHIP;
    expect(&ab, "amss.bin", "ath11k/WCN6855/hw2.0/amss.bin");
    ab.hw_rev = ATH11K_HW_WCN6855_HW21;
    ab.hw_params.fw.dir = "WCN6855/hw2.1";
    dt_override = "custom";
    expect(&ab, "amss.bin", "ath11k/WCN6855/hw2.1/custom/amss.bin");
    expect(&ab, "board-2.bin", "ath11k/WCN6855/hw2.1/board-2.bin");
    puts("PASS real ath11k C function: E108 selection, normal cards, hardware revisions and DT override");
    return 0;
}
C
cc -std=c11 -Wall -Wextra -Werror "$work/paths.c" -o "$work/paths"
"$work/paths"

# Failed downloads and changed upstream layouts must not install a partial set.
fixture="$work/source"
mkdir -p "$fixture/package/firmware/linux-firmware" "$fixture/package/kernel/mac80211" "$work/bin"
cp "$recipe" "$fixture/package/firmware/linux-firmware/"
cp "$src/package/kernel/mac80211/Makefile" "$fixture/package/kernel/mac80211/"
printf '#!/bin/sh\nexit 22\n' > "$work/bin/curl"
chmod 755 "$work/bin/curl"
mkdir -p "$fixture/dl/photonicat-nfa765-e108-273e26348fbd4c14320f6789e999b3211e696690"
printf 'corrupt cached firmware\n' > "$fixture/dl/photonicat-nfa765-e108-273e26348fbd4c14320f6789e999b3211e696690/amss.bin"
if PATH="$work/bin:$PATH" bash "$project/scripts/build/bundle-nfa765-e108.sh" "$fixture" >"$work/rejected.log" 2>&1; then fail 'Corrupt cache and offline download accepted'; fi
test ! -e "$fixture/files/lib/firmware/ath11k/WCN6855/hw2.0/nfa765-e108"
test ! -e "$fixture/package/kernel/mac80211/patches/ath11k/$patch_name"
sed -i 's|$(LN) ./hw2.0|$(LN) ./different|' "$fixture/package/firmware/linux-firmware/qca_ath11k.mk"
if bash "$project/scripts/build/bundle-nfa765-e108.sh" "$fixture" >"$work/rejected.log" 2>&1; then fail 'Changed upstream layout accepted'; fi
cmp "$recipe" "$work/recipe.before"
printf '%s\n' 'PASS failed-download protection and upstream-layout guard'
