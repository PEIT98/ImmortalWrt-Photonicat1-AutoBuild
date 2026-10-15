#
# Copyright (C) 2020 Russell Morris <rmorris@rkmorris.us>
#
# This is free software, licensed under the Apache License, Version 2.0 .
#

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI Battery Status
LUCI_DESCRIPTION:=Provides a battery charge indicator in LuCI.

LUCI_DEPENDS:=+luci-base +luci-app-photonicat-power

PKG_LICENSE:=Apache-2.0

define Package/luci-mod-battstatus/conffiles
/etc/config/luci_battstatus
endef

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature

