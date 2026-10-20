# SPDX-License-Identifier: GPL-3.0-or-later AND Apache-2.0
include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-photonicat-power
PKG_VERSION:=1.0.16
PKG_RELEASE:=4
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/photonicat/rockchip_rk3568_pcat_manager.git
PKG_SOURCE_DATE:=2025-08-18
PKG_SOURCE_VERSION:=6f16e4ab4fbba220af932e02e5ef8f1a63f4bafd
PKG_MIRROR_HASH:=skip
PKG_LICENSE:=GPL-3.0-or-later AND Apache-2.0
PKG_LICENSE_FILES:=LICENSE
PKG_INSTALL:=1
PKG_BUILD_DEPENDS:=luci-base/host

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/meson.mk

define Package/luci-app-photonicat-power
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Photonicat1 management and header status
  DEPENDS:=@TARGET_rockchip_armv8 +luci-base +socat +iw +glib2 +libjson-c
  CONFLICTS:=pcat-mgr pcat-manager pcat-manager-v1 luci-mod-battstatus luci-i18n-battstatus-zh-cn
endef

define Package/luci-app-photonicat-power/description
  Photonicat1 PMU daemon, management page and LuCI hardware status in one package.
endef

define Package/luci-app-photonicat-power/conffiles
/etc/pcat-manager.conf
/etc/pcat-manager-userdata.conf
/etc/config/luci_battstatus
endef

define Build/Prepare
	$(call Build/Prepare/Default)
	$(CP) ./files/modem-manager-noop.c $(PKG_BUILD_DIR)/src/modem-manager.c
	$(CP) ./files/meson-root.build $(PKG_BUILD_DIR)/meson.build
	$(CP) ./files/meson-src.build $(PKG_BUILD_DIR)/src/meson.build
	python3 ./files/patch-main.py $(PKG_BUILD_DIR)/src/main.c
	python3 ./files/patch-photonicat-ups.py $(PKG_BUILD_DIR)/src/pmu-manager.c
endef

define Package/luci-app-photonicat-power/install
	$(INSTALL_DIR) $(1)/usr/bin $(1)/etc/init.d $(1)/etc
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/pcat-manager $(1)/usr/bin/pcat-manager
	$(INSTALL_BIN) ./files/pcat-manager.init $(1)/etc/init.d/pcat-manager
	$(INSTALL_CONF) ./files/pcat-manager.conf $(1)/etc/pcat-manager.conf
	$(INSTALL_DIR) $(1)/www $(1)/usr/libexec/rpcd $(1)/usr/share/luci/menu.d $(1)/usr/share/rpcd/acl.d $(1)/etc/config
	$(CP) ./htdocs/. $(1)/www/
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/luci.photonicat_power $(1)/usr/libexec/rpcd/
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/luci.photonicat_header $(1)/usr/libexec/rpcd/
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/luci.battstatus $(1)/usr/libexec/rpcd/
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-photonicat-power.json $(1)/usr/share/luci/menu.d/
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-photonicat-power.json $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_CONF) ./root/etc/config/luci_battstatus $(1)/etc/config/luci_battstatus
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n $(1)/etc/uci-defaults
	po2lmo ./po/zh_Hans/battstatus.po $(1)/usr/lib/lua/luci/i18n/battstatus.zh-cn.lmo
	$(INSTALL_BIN) ./files/98-photonicat-battery-language $(1)/etc/uci-defaults/
endef

$(eval $(call BuildPackage,luci-app-photonicat-power))
