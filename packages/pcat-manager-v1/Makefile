# SPDX-License-Identifier: GPL-3.0-or-later
include $(TOPDIR)/rules.mk

PKG_NAME:=pcat-manager-v1
PKG_VERSION:=1.0.16
PKG_RELEASE:=1
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/photonicat/rockchip_rk3568_pcat_manager.git
PKG_SOURCE_DATE:=2025-08-18
PKG_SOURCE_VERSION:=6f16e4ab4fbba220af932e02e5ef8f1a63f4bafd
PKG_MIRROR_HASH:=skip
PKG_LICENSE:=GPL-3.0-or-later
PKG_LICENSE_FILES:=LICENSE
PKG_INSTALL:=1

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/meson.mk

define Package/pcat-manager-v1
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=Photonicat1 MCU power manager (PMU-only)
  DEPENDS:=@TARGET_rockchip_armv8 +glib2 +libjson-c
  CONFLICTS:=pcat-mgr pcat-manager
endef

define Package/pcat-manager-v1/description
  Official Photonicat v1 MCU power service with legacy modem and mwan3 control disabled.
endef

define Package/pcat-manager-v1/conffiles
/etc/pcat-manager.conf
/etc/pcat-manager-userdata.conf
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) ./files/modem-manager-noop.c $(PKG_BUILD_DIR)/src/modem-manager.c
	$(CP) ./files/meson-root.build $(PKG_BUILD_DIR)/meson.build
	$(CP) ./files/meson-src.build $(PKG_BUILD_DIR)/src/meson.build
	python3 ./files/patch-main.py $(PKG_BUILD_DIR)/src/main.c
	python3 ./files/patch-photonicat-ups.py $(PKG_BUILD_DIR)/src/pmu-manager.c
endef

define Package/pcat-manager-v1/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/etc/init.d $(1)/etc
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/pcat-manager $(1)/usr/bin/pcat-manager
	$(INSTALL_BIN) ./files/pcat-manager.init $(1)/etc/init.d/pcat-manager
	$(INSTALL_CONF) ./files/pcat-manager.conf $(1)/etc/pcat-manager.conf
endef

$(eval $(call BuildPackage,pcat-manager-v1))
