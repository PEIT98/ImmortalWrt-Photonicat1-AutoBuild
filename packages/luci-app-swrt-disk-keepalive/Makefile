include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-swrt-disk-keepalive
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=AGPL-3.0-only
PKG_MAINTAINER:=SlAlot
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-swrt-disk-keepalive
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=SWRT USB disk keepalive
  DEPENDS:=+luci-base +rpcd +jq-full +flock +coreutils-dd +coreutils-timeout +uci
endef

define Package/luci-app-swrt-disk-keepalive/conffiles
/etc/config/swrt_disk_keepalive
endef

define Build/Compile
endef

define Package/luci-app-swrt-disk-keepalive/install
	$(INSTALL_DIR) $(1)
	$(CP) ./root/. $(1)/
	chmod 755 $(1)/etc/init.d/swrt-disk-keepalive $(1)/usr/libexec/swrt-disk-keepalive $(1)/usr/libexec/rpcd/luci.swrt_disk_keepalive
endef

$(eval $(call BuildPackage,luci-app-swrt-disk-keepalive))
