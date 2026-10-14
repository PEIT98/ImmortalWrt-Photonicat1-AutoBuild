# CPU 调频 LuCI 插件（项目内置版本）

本目录直接保存 ImmortalWrt `openwrt-25.12` 分支的 `luci-app-cpufreq` 完整源码。

- 上游来源：`immortalwrt/luci/applications/luci-app-cpufreq`
- 引入时上游提交：`d6167ea0645cbd1327708d85f94824f42d0eb872`
- 原版版权和许可标识（GPL-3.0-only）保留在原文件中。
- `Makefile` 仅修改 `luci.mk` 引入路径，以便在 OpenWrt `package/luci-app-cpufreq` 下直接编译。
- 保留原版网页、LuCI 菜单、RPC 权限、简体中文翻译。
- CPU 频率调整的实际后端由 ImmortalWrt 官方 `cpufreq` 提供，不自行替换后台服务。

## 如何修改

- 网页布局与功能：`htdocs/luci-static/resources/view/cpufreq.js`
- 菜单：`root/usr/share/luci/menu.d/luci-app-cpufreq.json`
- RPC 权限：`root/usr/share/rpcd/acl.d/luci-app-cpufreq.json`
- 中文翻译：`po/zh_Hans/cpufreq.po`

构建时 `scripts/build/prepare.sh` 复制整个插件进 ImmortalWrt 本地软件包目录；Feeds 安装后移除 LuCI 官方同名符号链接，避免两份插件冲突。构建配置继续使用 `CONFIG_PACKAGE_luci-app-cpufreq=y` 和 `CONFIG_PACKAGE_cpufreq=y`。

注意：本地副本不会自动跟随上游更新；后续可审阅上游变更再同步。暂未进行新固件实编译验证。
