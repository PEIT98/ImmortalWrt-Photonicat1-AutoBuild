#!/bin/sh
# 功能：修正频段顺序，并按实际频段生成 Photonicat Wi-Fi 名称及密码。
# 使用本次编译的上游检测脚本；已有无线配置不会被覆盖，新装网卡也使用这些默认值。
set -eu
SRC="${1:?需要 ImmortalWrt 根目录}"
FROM="$SRC/package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
TO="$SRC/files/lib/wifi/mac80211.uc"
[ -f "$FROM" ] || { echo '::error::找不到 mac80211.uc，无法设置 Wi-Fi 默认名称和密码' >&2; exit 1; }
mkdir -p "$(dirname "$TO")"
python3 - "$FROM" "$TO" <<'PY'
from pathlib import Path
import re, sys
src, dest = map(Path, sys.argv[1:3])
data = src.read_text()
pattern = r'^const bands_order\s*=\s*\[[^\n]*\];'
match = re.search(pattern, data, re.M)
if not match:
    raise SystemExit('::error::上游 mac80211.uc 的频段定义已变更，请检查 Wi-Fi 默认配置')
updated = data[:match.start()] + '''const bands_order = [ "2G", "5G", "6G", "60G" ];
const photonicat_defaults = {
	"2g": { ssid: "Photonicat", encryption: "psk2", key: "photonicat" },
	"5g": { ssid: "Photonicat-5G", encryption: "psk2", key: "photonicat" }
};''' + data[match.end():]
replacements = {
    '${defaults?.ssid || "ImmortalWrt"}': '${photonicat_defaults[band_name]?.ssid || defaults?.ssid || "Photonicat"}',
    '${defaults?.encryption || encryption}': '${photonicat_defaults[band_name]?.encryption || defaults?.encryption || encryption}',
    '${defaults?.key || ""}': '${photonicat_defaults[band_name]?.key || defaults?.key || ""}',
}
for old, new in replacements.items():
    if updated.count(old) != 1:
        raise SystemExit(f'::error::上游 Wi-Fi 配置格式已变更，无法应用默认设置：{old}')
    updated = updated.replace(old, new)
dest.write_text(updated)
print('Wi-Fi 默认值：Photonicat-2.4G / Photonicat-5G，WPA2-PSK，密码 photonicat')
PY
