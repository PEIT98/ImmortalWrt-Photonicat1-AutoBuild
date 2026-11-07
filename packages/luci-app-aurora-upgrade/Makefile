include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-aurora-upgrade
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-3.0-or-later
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-aurora-upgrade
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Aurora verified GitHub release updater
  DEPENDS:=@TARGET_rockchip_armv8 +luci-base +rpcd +curl +ca-bundle +jq-full +flock +coreutils-sha256sum +coreutils-stat +uci
endef

define Package/luci-app-aurora-upgrade/conffiles
/etc/config/aurora_update
endef

define Build/Compile
endef

define Package/luci-app-aurora-upgrade/install
	$(INSTALL_DIR) $(1)
	$(CP) ./root/. $(1)/
	chmod 755 $(1)/usr/libexec/aurora-update $(1)/usr/libexec/rpcd/luci.aurora_update
endef

$(eval $(call BuildPackage,luci-app-aurora-upgrade))
