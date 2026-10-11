#!/usr/bin/env bash
set -euo pipefail
REF="${1:?缺少光影猫参考仓库路径}"
SRC="${2:?缺少 ImmortalWrt 源码路径}"
OVERLAY="${3:?缺少项目 files 覆盖目录}"
test -f "$REF/.config"
test -f "$REF/feeds.conf.default"
test -f "$SRC/Makefile"
cp -f "$REF/.config" "$SRC/.config"
cp -f "$REF/feeds.conf.default" "$SRC/feeds.conf.default"

# QModem 官方 feed，每次构建从 main 更新源码。
if ! grep -Eq '^src-git qmodem ' "$SRC/feeds.conf.default"; then
  printf '\nsrc-git qmodem https://github.com/FUjr/QModem.git;main\n' >> "$SRC/feeds.conf.default"
fi

python3 - "$SRC/.config" <<'PY'
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
original = p.read_text()
remove_exact = {
    'luci-app-modemband', 'luci-i18n-modemband-zh-cn', 'modemband',
    'luci-app-sms-tool-js', 'luci-i18n-sms-tool-js-zh-cn', 'sms-tool',
    'luci-app-qmodem', 'luci-app-qmodem-sms', 'luci-app-qmodem-mwan',
    'luci-app-passwall', 'luci-i18n-passwall-zh-cn',
    'luci-app-smartdns', 'luci-i18n-smartdns-zh-cn', 'smartdns',
    'luci-app-zerotier', 'luci-i18n-zerotier-zh-cn', 'zerotier',
}
remove_prefixes = ('luci-app-passwall_INCLUDE_',)
force = {
    'qmodem': 'y', 'luci-app-qmodem-next': 'y',
    'qmodem_INCLUDE_generic-qmi-wwan': 'y',
    'qmodem_INCLUDE_vendor-qmi-wwan': 'n',
    'qmodem_INCLUDE_nss-qmi-wwan': 'n',
    'luci-app-mwan3': 'y', 'luci-i18n-mwan3-zh-cn': 'y', 'mwan3': 'y',
    'luci-app-clash': 'y',
    'cpufreq': 'y', 'luci-app-cpufreq': 'y', 'luci-i18n-cpufreq-zh-cn': 'y',
    'luci-mod-battstatus': 'y', 'luci-i18n-battstatus-zh-cn': 'y',
    'kmod-ath11k-pci': 'y', 'ath11k-firmware-wcn6855': 'y',
    'kmod-usb-net-qmi-wwan': 'y', 'kmod-usb-net-cdc-mbim': 'y',
    'kmod-usb-serial-option': 'y',
}
removed = set(remove_exact)
kept = []
for line in original.splitlines():
    m = re.match(r'(?:# )?CONFIG_PACKAGE_([\w+.-]+)(?:=| is not set)', line)
    if m:
        k = m.group(1)
        if k in force or k in remove_exact or k.startswith(remove_prefixes):
            if k not in force:
                removed.add(k)
            continue
    kept.append(line)
kept += ['', '# Photonicat1 + QModem (auto-generated overrides)']
for k in sorted(removed - set(force)):
    kept.append(f'# CONFIG_PACKAGE_{k} is not set')
for k, v in sorted(force.items()):
    kept.append(f'CONFIG_PACKAGE_{k}=y' if v == 'y' else f'# CONFIG_PACKAGE_{k} is not set')
p.write_text('\n'.join(kept) + '\n')
PY

# 不引入参考仓库的 Wi-Fi 密码、静态 USB0 拨号与其它网络预设。
mkdir -p "$SRC/files"
cp -a "$OVERLAY/." "$SRC/files/"
echo '配置就绪：QModem Next (集成短信) + mwan3 + Clash + cpufreq + battstatus'
echo '已排除旧 ModemBand、旧短信、PassWall、SmartDNS、ZeroTier'
echo '首次使用：QModem 模组别名设置 wwan_5g，Wi-Fi STA 绑定 wwan'
