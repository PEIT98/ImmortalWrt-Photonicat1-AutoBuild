#!/usr/bin/env bash
# 功能：核对目标设备、插件、驱动及关键依赖。
set -euo pipefail
CFG="${1:-.config}"
need=(
  CONFIG_TARGET_rockchip_armv8_DEVICE_ariaboard_photonicat
  CONFIG_DEVEL
  CONFIG_CCACHE
  CONFIG_PACKAGE_qmodem
  CONFIG_PACKAGE_luci-app-qmodem-next
  CONFIG_PACKAGE_sms-forwarder-next
  CONFIG_PACKAGE_luci-app-mwan3
  CONFIG_PACKAGE_mwan3
  CONFIG_PACKAGE_luci-app-openclash
  CONFIG_PACKAGE_luci-app-ttyd
  CONFIG_PACKAGE_ttyd
  CONFIG_PACKAGE_luci-theme-aurora
  CONFIG_PACKAGE_luci-compat
  CONFIG_PACKAGE_luci-app-store
  CONFIG_PACKAGE_luci-lib-taskd
  CONFIG_PACKAGE_luci-lib-xterm
  CONFIG_PACKAGE_taskd
  CONFIG_PACKAGE_script-utils
  CONFIG_PACKAGE_coreutils-stty
  CONFIG_PACKAGE_mount-utils
  CONFIG_PACKAGE_tar
  CONFIG_PACKAGE_xz-utils
  CONFIG_PACKAGE_luci-app-dockerman
  CONFIG_PACKAGE_docker
  CONFIG_PACKAGE_dockerd
  CONFIG_PACKAGE_docker-compose
  CONFIG_PACKAGE_luci-app-bandix-plus
  CONFIG_PACKAGE_bandix-plus
  CONFIG_PACKAGE_luci-app-diskman
  CONFIG_PACKAGE_luci-app-diskman_INCLUDE_lsblk
  CONFIG_PACKAGE_usbutils
  CONFIG_PACKAGE_pciutils
  CONFIG_PACKAGE_lsblk
  CONFIG_PACKAGE_iperf3
  CONFIG_PACKAGE_tcpdump
  CONFIG_PACKAGE_kmod-usb-acm
  CONFIG_PACKAGE_luci-app-autoreboot
  CONFIG_PACKAGE_luci-app-upnp
  CONFIG_PACKAGE_luci-i18n-diskman-zh-cn
  CONFIG_PACKAGE_luci-i18n-autoreboot-zh-cn
  CONFIG_PACKAGE_luci-i18n-upnp-zh-cn
  CONFIG_PACKAGE_kmod-rtw89-8922ae
  CONFIG_PACKAGE_kmod-rtw89-8852be
  CONFIG_PACKAGE_kmod-rtw89-8852ce
  CONFIG_PACKAGE_kmod-mt7925e
  CONFIG_PACKAGE_kmod-mt7921e
  CONFIG_PACKAGE_kmod-mt7915e
  CONFIG_PACKAGE_kmod-mt7925-firmware
  CONFIG_PACKAGE_kmod-mt7916-firmware
  CONFIG_PACKAGE_kmod-ath12k
  CONFIG_PACKAGE_ath12k-firmware-wcn7850
  CONFIG_PACKAGE_kmod-ath10k
  CONFIG_PACKAGE_ath10k-firmware-qca988x
  CONFIG_PACKAGE_kmod-mmc
  CONFIG_PACKAGE_ath10k-firmware-qca9377-sdio
  CONFIG_PACKAGE_ath10k-board-qca9377-sdio
  CONFIG_PACKAGE_luci-app-cpufreq
  CONFIG_PACKAGE_cpufreq
  CONFIG_PACKAGE_luci-mod-battstatus
  CONFIG_PACKAGE_luci-app-photonicat-power
  CONFIG_PACKAGE_socat
  CONFIG_PACKAGE_kmod-ath11k-pci
  CONFIG_PACKAGE_ath11k-firmware-wcn6855
  CONFIG_PACKAGE_kmod-usb-net-qmi-wwan
  CONFIG_PACKAGE_kmod-usb-net-cdc-mbim
  CONFIG_PACKAGE_kmod-usb-serial-option
)
failed=0
for f in CONFIG_DRIVER_11AC_SUPPORT CONFIG_DRIVER_11AX_SUPPORT CONFIG_DRIVER_11BE_SUPPORT; do
  if grep -Fxq "$f=y" "$CFG"; then
    echo "OK: $f=y"
  else
    echo "::error::缺少 Wi-Fi 5/6/7 驱动功能开关 $f" >&2
    failed=1
  fi
done
if grep -Fxq '# CONFIG_RUBY_ENABLE_YJIT is not set' "$CFG"; then
  echo '通过：Ruby YJIT 已关闭，避免大型 Rust 构建依赖'
else
  echo '::error::Ruby YJIT 仍然启用，将触发耗费空间的 Rust 编译' >&2
  failed=1
fi
if grep -Fxq '# CONFIG_PACKAGE_luci-app-diskman_INCLUDE_btrfs_progs is not set' "$CFG"; then
  echo '通过：DiskMan 可选 Btrfs 组件已关闭，降低编译负担'
else
  echo '::error::DiskMan 附加 Btrfs 工具链未关闭，请检查 25.12 Kconfig 选项是否变化' >&2
  failed=1
fi
echo '===== 配置校验：全部必选项 ====='
for key in "${need[@]}"; do
  if grep -Fxq "$key=y" "$CFG"; then
    echo "OK: $key=y"
  else
    current=$(grep -E "^(${key}=|# ${key} is not set)" "$CFG" | head -n 1 || true)
    echo "::error::缺少必选项 $key=y；当前：${current:-完全不存在（软件源缺失或依赖未满足）}" >&2
    failed=1
  fi
done
absent=(
  CONFIG_PACKAGE_luci-app-modemband
  CONFIG_PACKAGE_luci-app-sms-tool-js
  CONFIG_PACKAGE_luci-app-qmodem
  CONFIG_PACKAGE_luci-app-qmodem-sms
  CONFIG_PACKAGE_luci-app-qmodem-mwan
  CONFIG_PACKAGE_luci-app-clash
  CONFIG_PACKAGE_luci-app-passwall
  CONFIG_PACKAGE_luci-app-smartdns
  CONFIG_PACKAGE_luci-app-zerotier
  CONFIG_PACKAGE_luci-app-online-upgrade
  CONFIG_PACKAGE_kmod-ath10k-sdio
  CONFIG_PACKAGE_smartdns
  CONFIG_PACKAGE_zerotier
)
for key in "${absent[@]}"; do
  if grep -Fxq "$key=y" "$CFG"; then
    echo "::error::仍安装不需要或与 Next 冲突的软件包 $key" >&2
    failed=1
  fi
done
# stable 版将 QMI 驱动选择定义在传统 LuCI 包中；这里直接核验通用内核驱动。
if [ "$failed" -ne 0 ]; then
  echo '::error::软件包配置校验未通过，请查看丢失的项目，并下载构建配置 Artifact 排查缺失依赖。' >&2
  exit 1
fi
echo '光影猫一代目标、QModem、OpenClash、Aurora、iStore、Docker/Dockerman、DiskMan、USB/PCIe/网络诊断、ACM、定时重启、UPnP、QCA9377 SDIO 固件及 Wi-Fi 驱动选择检查通过。'
