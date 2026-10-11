#!/usr/bin/env bash
set -euo pipefail
CFG="${1:-.config}"
need=(
  CONFIG_TARGET_rockchip_armv8_DEVICE_ariaboard_photonicat
  CONFIG_PACKAGE_qmodem
  CONFIG_PACKAGE_luci-app-qmodem-next
  CONFIG_PACKAGE_qmodem-smsd
  CONFIG_PACKAGE_sms-forwarder-next
  CONFIG_PACKAGE_luci-app-mwan3
  CONFIG_PACKAGE_mwan3
  CONFIG_PACKAGE_luci-app-clash
  CONFIG_PACKAGE_luci-app-cpufreq
  CONFIG_PACKAGE_cpufreq
  CONFIG_PACKAGE_luci-mod-battstatus
  CONFIG_PACKAGE_kmod-ath11k-pci
  CONFIG_PACKAGE_ath11k-firmware-wcn6855
  CONFIG_PACKAGE_kmod-usb-net-qmi-wwan
  CONFIG_PACKAGE_kmod-usb-net-cdc-mbim
  CONFIG_PACKAGE_kmod-usb-serial-option
)
for key in "${need[@]}"; do
  if ! grep -Fxq "$key=y" "$CFG"; then
    echo "::error::缺少必要选项 $key=y" >&2
    exit 1
  fi
done
absent=(
  CONFIG_PACKAGE_luci-app-modemband
  CONFIG_PACKAGE_luci-app-sms-tool-js
  CONFIG_PACKAGE_luci-app-qmodem
  CONFIG_PACKAGE_luci-app-qmodem-sms
  CONFIG_PACKAGE_luci-app-qmodem-mwan
  CONFIG_PACKAGE_luci-app-passwall
  CONFIG_PACKAGE_luci-app-smartdns
  CONFIG_PACKAGE_luci-app-zerotier
  CONFIG_PACKAGE_smartdns
  CONFIG_PACKAGE_zerotier
)
for key in "${absent[@]}"; do
  if grep -Fxq "$key=y" "$CFG"; then
    echo "::error::仍安装不需要或与 Next 冲突的软件包 $key" >&2
    exit 1
  fi
done
if ! grep -Fxq 'CONFIG_PACKAGE_qmodem_INCLUDE_generic-qmi-wwan=y' "$CFG"; then
  echo '::error::通用 QMI WWAN 驱动选择丢失' >&2
  exit 1
fi
echo '光影猫一代目标、QModem Next 短信、mwan3、Clash、cpufreq、电池状态及驱动检查通过。'
