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
	"5g": { ssid: "Pwrt-5G", encryption: "psk2", key: "photonicat" },
	"2g": { ssid: "Pwrt-2.4G", encryption: "psk2", key: "photonicat" }
};

function photonicat_radio_bands(radios, onboard_sdio) {
	let preferred = onboard_sdio ? onboard_sdio_bands_order : bands_order;
	// wifi-detect only sets default_channel when the driver has an enabled channel.
	let selected = map(radios, (r) => filter(preferred,
		(b) => r.bands[b]?.default_channel)[0]);
	if (onboard_sdio || length(radios) < 2)
		return selected;

	// Only separate hardware radios can receive different bands simultaneously.
	for (let i, a in radios) {
		if (!a.bands["5G"]?.default_channel)
			continue;
		for (let j, b in radios) {
			if (i == j || !b.bands["2G"]?.default_channel)
				continue;
			selected[i] = "5G";
			selected[j] = "2G";
			return selected;
		}
	}
	return selected;
}' pc_awk '
match($0,/^const bands_order[[:space:]]*=[[:space:]]*\[[^\n]*\];/) { n++; print ENVIRON["PC_BANDS"] substr($0,RSTART+RLENGTH); next }
{print}
END {if(n!=1) exit 1}'
pc_replace 'for (let radio in radios) {' 'let onboard_sdio = phy.path && (match(phy.path, /(^|\/)mmc_host\//) || match(phy.path, /\.mmc\//));
	let radio_bands = photonicat_radio_bands(radios, onboard_sdio);
	for (let radio_idx, radio in radios) {' 'Wi-Fi 射频配置'
pc_replace 'let band_name = filter(bands_order, (b) => radio.bands[b])[0];' 'let band_name = radio_bands[radio_idx];' 'Wi-Fi 默认配置'
# 沿用驱动检测到的首个可用信道，通常是 36；不强制使用被禁用的信道。
pc_replace 'let htmode = filter(htmode_order, (m) => band[lc(m)])[0];' 'let htmode = band_name == "5G" && band.he ? "HE" : filter(htmode_order, (m) => band[lc(m)])[0];' 'Wi-Fi 默认配置'
pc_replace '${defaults?.ssid || "ImmortalWrt"}' '${onboard_sdio ? "Pwrt" : (photonicat_defaults[band_name]?.ssid || defaults?.ssid || "Pwrt")}' 'Wi-Fi 默认配置'
pc_replace '${defaults?.encryption || encryption}' '${photonicat_defaults[band_name]?.encryption || defaults?.encryption || encryption}' 'Wi-Fi 默认配置'
pc_replace '${defaults?.key || ""}' '${photonicat_defaults[band_name]?.key || defaults?.key || ""}' 'Wi-Fi 默认配置'
mkdir -p "$(dirname "$to")"
# 上游文件保持不变，生成默认值覆盖文件。
cat "$PC_WORK" > "$to"
echo "Wi-Fi 默认值：板载 Pwrt；M.2 优先 Pwrt-5G，可用频段回退为 Pwrt-2.4G；双射频分别配置 5G/2.4G。"
