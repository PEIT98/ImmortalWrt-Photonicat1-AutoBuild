#!/usr/bin/env python3
"""Apply packages *after* feeds install, otherwise feed installation rewrites .config."""
from pathlib import Path
import re, sys
p = Path(sys.argv[1])
original = p.read_text()
remove_exact = {
    'luci-app-modemband', 'luci-i18n-modemband-zh-cn', 'modemband',
    'luci-app-sms-tool-js', 'luci-i18n-sms-tool-js-zh-cn', 'sms-tool',
    'luci-app-qmodem', 'luci-app-qmodem-sms', 'luci-app-qmodem-mwan', 'luci-app-clash',
    'luci-app-passwall', 'luci-i18n-passwall-zh-cn',
    'luci-app-smartdns', 'luci-i18n-smartdns-zh-cn', 'smartdns',
    'luci-app-zerotier', 'luci-i18n-zerotier-zh-cn', 'zerotier',
}
remove_prefixes = ('luci-app-passwall_INCLUDE_',)
force = {
    'qmodem': 'y', 'luci-app-qmodem-next': 'y',
    'sms-forwarder-next': 'y',
    'luci-app-mwan3': 'y', 'luci-i18n-mwan3-zh-cn': 'y', 'mwan3': 'y',
    'luci-app-openclash': 'y',
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