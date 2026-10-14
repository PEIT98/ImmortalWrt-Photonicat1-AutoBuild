#!/usr/bin/env python3
# 功能：为板载 QCA9377 增加 ath10k SDIO 支持，并保留 PCIe 支持。
"""在同一个 kmod-ath10k 内加入 PCIe 和 SDIO 驱动。不能同时选择共享 ath10k_core.ko 的两个变体。"""
from pathlib import Path
import sys

src = Path(sys.argv[1]).resolve()
ath = src / "package/kernel/mac80211/ath.mk"
if not ath.is_file():
    raise SystemExit(f"ERROR: cannot find {ath}")

original = ath.read_text(encoding="utf-8")
config_from = "config-$(call config_package,ath10k,regular) += ATH10K ATH10K_PCI\n"
config_to = "config-$(call config_package,ath10k,regular) += ATH10K ATH10K_PCI ATH10K_SDIO\n"
package_from = """define KernelPackage/ath10k
  $(call KernelPackage/ath10k/Default)
  VARIANT:=regular
  DEFAULT_VARIANT:=1
endef"""
package_to = """define KernelPackage/ath10k
  $(call KernelPackage/ath10k/Default)
  # Photonicat1 onboard QCA9377/"QCA1023" uses SDIO; keep PCI cards working.
  DEPENDS+= +kmod-mmc
  FILES+= $(PKG_BUILD_DIR)/drivers/net/wireless/ath/ath10k/ath10k_sdio.ko
  AUTOLOAD:=$(call AutoProbe,ath10k_core ath10k_pci ath10k_sdio)
  VARIANT:=regular
  DEFAULT_VARIANT:=1
endef"""

if config_to in original and package_to in original:
    print("Photonicat1 ath10k PCI+SDIO patch already active")
    raise SystemExit(0)
for needle in (config_from, package_from):
    if original.count(needle) != 1:
        raise SystemExit(f"ERROR: ath.mk upstream structure changed: {needle[:70]!r}")

updated = original.replace(config_from, config_to, 1).replace(package_from, package_to, 1)
if updated.count("ATH10K ATH10K_PCI ATH10K_SDIO") != 1:
    raise SystemExit("ERROR: combined ath10k feature not enabled")
if updated.count("FILES+= $(PKG_BUILD_DIR)/drivers/net/wireless/ath/ath10k/ath10k_sdio.ko") != 1:
    raise SystemExit("ERROR: SDIO driver file not registered")

ath.write_text(updated, encoding="utf-8")
print("Enabled ath10k PCI + SDIO in regular kmod-ath10k; shared core remains single-owner.")
