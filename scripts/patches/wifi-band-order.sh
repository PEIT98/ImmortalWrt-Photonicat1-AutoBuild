#!/bin/sh
# 构建主机脚本：先校验，再提交全部文本修改。
set -eu
. "$(dirname "$0")/../lib/patch.sh"
root=${1:?需要 ImmortalWrt 根目录}
from="$root/package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
to="$root/files/lib/wifi/mac80211.uc"
pc_init
pc_load "$from"
PC_BANDS='const bands_order = [ "5G", "2G", "6G", "60G" ];
const onboard_sdio_bands_order = [ "2G", "5G", "6G", "60G" ];
const photonicat_defaults = {
	"5g": { ssid: "Photonicat-Wrt", encryption: "psk2", key: "photonicat" },
	"2g": { ssid: "Photonicat-Wrt", encryption: "psk2", key: "photonicat" }
};' pc_awk '
match($0,/^const bands_order[[:space:]]*=[[:space:]]*\[[^\n]*\];/) { n++; print ENVIRON["PC_BANDS"] substr($0,RSTART+RLENGTH); next }
{print}
END {if(n!=1) exit 1}'
pc_replace 'let band_name = filter(bands_order, (b) => radio.bands[b])[0];' 'let onboard_sdio = phy.path && (match(phy.path, /(^|\/)mmc_host\//) || match(phy.path, /\.mmc\//));
		let preferred_bands = onboard_sdio ? onboard_sdio_bands_order : bands_order;
		let band_name = filter(preferred_bands, (b) => radio.bands[b])[0];' 'Wi-Fi 默认配置'
pc_replace 'let channel = rband.default_channel ?? "auto";' 'let channel = band_name == "5G" ? 36 : (rband.default_channel ?? "auto");' 'Wi-Fi 默认配置'
pc_replace 'let htmode = filter(htmode_order, (m) => band[lc(m)])[0];' 'let htmode = band_name == "5G" && band.he ? "HE" : filter(htmode_order, (m) => band[lc(m)])[0];' 'Wi-Fi 默认配置'
pc_replace '${defaults?.ssid || "ImmortalWrt"}' '${photonicat_defaults[band_name]?.ssid || defaults?.ssid || "Photonicat-Wrt"}' 'Wi-Fi 默认配置'
pc_replace '${defaults?.encryption || encryption}' '${photonicat_defaults[band_name]?.encryption || defaults?.encryption || encryption}' 'Wi-Fi 默认配置'
pc_replace '${defaults?.key || ""}' '${photonicat_defaults[band_name]?.key || defaults?.key || ""}' 'Wi-Fi 默认配置'
mkdir -p "$(dirname "$to")"
# 上游文件保持不变，生成默认值覆盖文件。
cat "$PC_WORK" > "$to"
echo "Wi-Fi 默认值：板载 SDIO 优先 2.4GHz，其他网卡优先 5GHz，保留能力回退。"
