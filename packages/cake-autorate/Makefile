# SPDX-License-Identifier: GPL-2.0-only
include $(TOPDIR)/rules.mk

PKG_NAME:=cake-autorate
PKG_VERSION:=3.2.1
PKG_RELEASE:=1
PKG_SOURCE_VERSION:=495038fd673a2146be08c2c4b76f77125c3c274b
PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/lynxthecat/cake-autorate/tar.gz/$(PKG_SOURCE_VERSION)?
PKG_HASH:=a4548b80ebbe2641f239aef06dd4fdf9054eec3b3ec197dab0fd2358cbb088ed
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_SOURCE_VERSION)
PKG_LICENSE:=GPL-2.0-only
PKG_LICENSE_FILES:=LICENCE.md

include $(INCLUDE_DIR)/package.mk

define Package/cake-autorate
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Adaptive CAKE bandwidth for variable-rate links
  URL:=https://github.com/lynxthecat/cake-autorate
  PKGARCH:=all
  DEPENDS:=+bash +fping +tc-full +jsonfilter +mwan3 +sqm-scripts
endef

define Package/cake-autorate/description
  Upstream stable cake-autorate with a disabled-by-default OpenWrt service.
  Resolve the actual QModem interface, require configured SQM CAKE queues,
  and bind latency probes to that interface through mwan3.
endef

define Package/cake-autorate/conffiles
/etc/config/cake-autorate
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/cake-autorate/install
	$(INSTALL_DIR) $(1)/usr/lib/cake-autorate
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/cake-autorate.sh $(1)/usr/lib/cake-autorate/
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/defaults.sh $(PKG_BUILD_DIR)/lib.sh $(1)/usr/lib/cake-autorate/
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d $(1)/etc/hotplug.d/iface $(1)/usr/libexec
	$(INSTALL_CONF) ./files/cake-autorate.config $(1)/etc/config/cake-autorate
	$(INSTALL_BIN) ./files/cake-autorate.init $(1)/etc/init.d/cake-autorate
	$(INSTALL_BIN) ./files/cake-autorate-prepare $(1)/usr/libexec/cake-autorate-prepare
	$(INSTALL_BIN) ./files/98-cake-autorate $(1)/etc/hotplug.d/iface/98-cake-autorate
	$(INSTALL_DIR) $(1)/usr/share/doc/cake-autorate
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/LICENCE.md ./README.md $(1)/usr/share/doc/cake-autorate/
endef

$(eval $(call BuildPackage,cake-autorate))
