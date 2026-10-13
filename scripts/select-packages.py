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
    # LuCI web terminal + official Aurora theme
    'luci-app-ttyd': 'y', 'ttyd': 'y', 'luci-theme-aurora': 'y',
    # Official LinkEase iStore and legacy Lua LuCI compatibility.
    'luci-app-store': 'y', 'luci-compat': 'y',
    # Docker Engine + CLI + Compose and LuCI Dockerman management UI.
    'luci-app-dockerman': 'y', 'docker': 'y', 'dockerd': 'y',
    'docker-compose': 'y',
    # Multi-interface traffic monitor (prebuilt aarch64 backend; disabled by default).
    'luci-app-bandix-plus': 'y', 'bandix-plus': 'y',
    # DiskMan uses ImmortalWrt 25.12 official LuCI feed; keep lsblk but skip optional Btrfs/RAID toolchains.
    'luci-app-diskman': 'y', 'luci-app-diskman_INCLUDE_lsblk': 'y',
    'luci-app-diskman_INCLUDE_btrfs_progs': 'n',
    # Hardware and network diagnostics for USB/PCIe modems and storage.
    'usbutils': 'y', 'pciutils': 'y', 'lsblk': 'y',
    'iperf3': 'y', 'tcpdump': 'y', 'kmod-usb-acm': 'y',
    # LuCI utilities; scheduled reboot and UPnP are not preconfigured/enabled here.
    'luci-app-autoreboot': 'y', 'luci-app-upnp': 'y',
    # Simplified Chinese LuCI translations available in official 25.12 feed.
    'luci-i18n-diskman-zh-cn': 'y', 'luci-i18n-autoreboot-zh-cn': 'y',
    'luci-i18n-upnp-zh-cn': 'y',
    # Realtek RTL8922AE / 8852BE / 8852CE (rtw89)
    'kmod-rtw89-8922ae': 'y', 'kmod-rtw89-8852be': 'y', 'kmod-rtw89-8852ce': 'y',
    # MediaTek MT7925, MT7921/MT7922 and MT7916
    'kmod-mt7925e': 'y', 'kmod-mt7921e': 'y', 'kmod-mt7915e': 'y',
    'kmod-mt7925-firmware': 'y', 'kmod-mt7916-firmware': 'y',
    # Qualcomm QCNCM865 (WCN7850), QCA9880/9882 (QCA988X)
    'kmod-ath12k': 'y', 'ath12k-firmware-wcn7850': 'y',
    'kmod-ath10k': 'y', 'ath10k-firmware-qca988x': 'y',
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
# Ensure 802.11ac/ax/be support so Wi-Fi 7 PCIe drivers are not dropped by defconfig.
kept = [line for line in kept if not re.match(r'(?:# )?CONFIG_DRIVER_11(?:AC|AX|BE)_SUPPORT(?:=| is not set)', line)]
kept += ['CONFIG_DRIVER_11AC_SUPPORT=y', 'CONFIG_DRIVER_11AX_SUPPORT=y', 'CONFIG_DRIVER_11BE_SUPPORT=y']
# OpenClash 依赖 Ruby，ARM64 默认启用 YJIT 会触发庞大的 Rust/host 构建。
# 关闭可选 YJIT，不影响 Ruby 与 OpenClash 常规工作。
kept = [line for line in kept if not re.match(r'(?:# )?CONFIG_RUBY_ENABLE_YJIT(?:=| is not set)', line)]
kept.append('# CONFIG_RUBY_ENABLE_YJIT is not set')
# Persist OpenWrt compiler objects across GitHub Actions runs (no build_dir cache).
# Config-devel.in declares CONFIG_CCACHE only when CONFIG_DEVEL is enabled.
# Without CONFIG_DEVEL=y, 'make defconfig' silently discards CONFIG_CCACHE=y.
kept = [line for line in kept if not re.match(r'(?:# )?CONFIG_DEVEL(?:=| is not set)', line)
        and not re.match(r'(?:# )?CONFIG_CCACHE(?:=| is not set)', line)
        and not re.match(r'(?:# )?CONFIG_CCACHE_DIR(?:=| is not set)', line)]
kept += ['CONFIG_DEVEL=y', 'CONFIG_CCACHE=y', 'CONFIG_CCACHE_DIR=""']
p.write_text('\n'.join(kept) + '\n')