#!/bin/sh
# 功能：优先选择 5GHz，默认 AX / 80MHz / 36 信道，并按实际频段设置名称及密码。
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
updated = data[:match.start()] + '''const bands_order = [ "5G", "2G", "6G", "60G" ];
const photonicat_defaults = {
	"5g": { ssid: "Photonicat-Wrt", encryption: "psk2", key: "photonicat" },
	"2g": { ssid: "Photonicat-Wrt", encryption: "psk2", key: "photonicat" }
};''' + data[match.end():]
replacements = {
    'let channel = rband.default_channel ?? "auto";': 'let channel = band_name == "5G" ? 36 : (rband.default_channel ?? "auto");',
    # 上游已按 max_width 限制到最多 80MHz；AX 网卡使用 HE，AC/N 网卡保留能力检测。
    'let htmode = filter(htmode_order, (m) => band[lc(m)])[0];': 'let htmode = band_name == "5G" && band.he ? "HE" : filter(htmode_order, (m) => band[lc(m)])[0];',
    '${defaults?.ssid || "ImmortalWrt"}': '${photonicat_defaults[band_name]?.ssid || defaults?.ssid || "Photonicat-Wrt"}',
    '${defaults?.encryption || encryption}': '${photonicat_defaults[band_name]?.encryption || defaults?.encryption || encryption}',
    '${defaults?.key || ""}': '${photonicat_defaults[band_name]?.key || defaults?.key || ""}',
}
for old, new in replacements.items():
    if updated.count(old) != 1:
        raise SystemExit(f'::error::上游 Wi-Fi 配置格式已变更，无法应用默认设置：{old}')
    updated = updated.replace(old, new)
dest.write_text(updated)
print('Wi-Fi 默认值：5GHz / 2.4GHz 名称均为 Photonicat-Wrt；优先 5GHz（支持 AX 时使用 HE80，信道 36），其次 2.4GHz；WPA2-PSK，密码 photonicat')
PY
