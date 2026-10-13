# SPDX-License-Identifier: GPL-2.0-only
# Based on gooyjq/luci-app-online-upgrade at pinned upstream commit.
# Photonicat1 hardening: check-only; no web flash, unsafe restore CGI, or auto APK install.
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-online-upgrade
PKG_VERSION:=1.0.0
PKG_RELEASE:=2
PKG_LICENSE:=GPL-2.0-only
PKG_MAINTAINER:=Photonicat1 community
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-online-upgrade
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Photonicat1 GitHub firmware update checker (read-only)
  DEPENDS:=+luci-base +curl +jsonfilter
endef

define Package/luci-app-online-upgrade/description
  Safe, read-only GitHub Releases update checker for Ariaboard Photonicat1.
  Does NOT download images or execute sysupgrade.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/luci-app-online-upgrade/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/online-upgrade.sh $(1)/usr/bin/online-upgrade.sh
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/online-upgrade $(1)/etc/config/online-upgrade
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-online-upgrade.json $(1)/usr/share/luci/menu.d/luci-app-online-upgrade.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-online-upgrade.json $(1)/usr/share/rpcd/acl.d/luci-app-online-upgrade.json
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/system
	$(INSTALL_DATA) ./root/www/luci-static/resources/view/system/online-upgrade.js $(1)/www/luci-static/resources/view/system/online-upgrade.js
endef

$(eval $(call BuildPackage,luci-app-online-upgrade))
