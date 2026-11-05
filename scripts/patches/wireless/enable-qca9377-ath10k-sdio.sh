#!/bin/sh
# 构建主机脚本：先校验，再提交全部文本修改。
set -eu
. "$(dirname "$0")/../../lib/patch.sh"
pc_init
pc_load "${1:?需要 ImmortalWrt 根目录}/package/kernel/mac80211/ath.mk"
pc_replace 'config-$(call config_package,ath10k,regular) += ATH10K ATH10K_PCI
' 'config-$(call config_package,ath10k,regular) += ATH10K ATH10K_PCI ATH10K_SDIO
' 'ath10k 功能配置'
pc_replace 'define KernelPackage/ath10k
  $(call KernelPackage/ath10k/Default)
  VARIANT:=regular
  DEFAULT_VARIANT:=1
endef' 'define KernelPackage/ath10k
  $(call KernelPackage/ath10k/Default)
  # Photonicat1 onboard QCA9377/"QCA1023" uses SDIO; keep PCI cards working.
  DEPENDS+= +kmod-mmc
  FILES+= $(PKG_BUILD_DIR)/drivers/net/wireless/ath/ath10k/ath10k_sdio.ko
  AUTOLOAD:=$(call AutoProbe,ath10k_core ath10k_pci ath10k_sdio)
  VARIANT:=regular
  DEFAULT_VARIANT:=1
endef' 'ath10k 驱动包'
pc_commit
echo "Enabled ath10k PCI + SDIO in regular kmod-ath10k."
