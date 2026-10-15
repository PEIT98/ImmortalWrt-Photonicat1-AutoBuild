# SPDX-License-Identifier: GPL-3.0-or-later
include $(TOPDIR)/rules.mk

LUCI_TITLE:=Photonicat1 Power Management
LUCI_DESCRIPTION:=Simple Photonicat v1 MCU power mode controller via official pcat-manager socket
LUCI_DEPENDS:=+luci-base +socat +pcat-manager-v1
PKG_LICENSE:=GPL-3.0-or-later

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
