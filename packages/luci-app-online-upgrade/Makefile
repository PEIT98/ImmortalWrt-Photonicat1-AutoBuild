include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-online-upgrade
PKG_VERSION:=2.0.0
PKG_RELEASE:=3
PKG_LICENSE:=AGPL-3.0-only
PKG_MAINTAINER:=SlAlot
PKGARCH:=all
PKG_LICENSE_FILES:=LICENSE

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-online-upgrade
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Pwrt verified online firmware upgrade
  DEPENDS:=@TARGET_rockchip_armv8 +luci-base +rpcd +curl +ca-bundle +jq-full +flock +coreutils-sha256sum +coreutils-stat +uci
endef

define Package/luci-app-online-upgrade/conffiles
/etc/config/swrt_upgrade
/etc/config/online-upgrade
endef

define Build/Compile
endef

define Package/luci-app-online-upgrade/install
	$(INSTALL_DIR) $(1)
	$(CP) ./root/. $(1)/
	chmod 755 $(1)/usr/libexec/swrt-upgrade $(1)/usr/libexec/rpcd/luci.swrt_upgrade
	chmod 755 $(1)/etc/uci-defaults/99-photonicat-upgrade-source
endef

$(eval $(call BuildPackage,luci-app-online-upgrade))
