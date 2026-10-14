# SPDX-License-Identifier: GPL-3.0-only
#
# Copyright (C) 2021-2022 ImmortalWrt.org

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI for CPU Freq Setting
LUCI_DEPENDS:=+cpufreq

# 本地插件位于 ImmortalWrt/package/luci-app-cpufreq，LuCI 构建规则使用官方 Feed。
include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
