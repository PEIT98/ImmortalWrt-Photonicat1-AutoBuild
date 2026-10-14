# 电池状态插件 luci-mod-battstatus

本目录完整保存 ImmortalWrt LuCI `openwrt-25.12` 分支的电池插件，并集成之前的 Aurora 显示修改。

上游源码：`immortalwrt/luci/modules/luci-mod-battstatus`，参考提交 `d6167ea0645cbd1327708d85f94824f42d0eb872`。保留 Apache-2.0 许可、原版 RPC 服务及全部多语言翻译。

- `Makefile`：仅调整 `luci.mk` 引用，使用官方 LuCI Feed 的构建规则
- `htdocs/luci-static/resources/preload/battstatus.js`：修改后的电池指示，保留 5 秒刷新、充电图标、低电量提示和 Aurora 紧凑样式
- `root/usr/libexec/rpcd/luci.battstatus`：上游原版电池状态后端，保留光影猫一代的 `pcat-battery`、`pcat-charger` 读取路径和执行权限
- `root/usr/share/rpcd/acl.d/luci-mod-battstatus.json`：上游原版权限文件
- `po/`：全部上游语言翻译，包含简体中文、繁体中文和翻译模板

## 构建方式

`scripts/build/prepare.sh` 将本目录复制到 `immortalwrt/package/luci-mod-battstatus`。安装 Feeds 后，工作流只移除官方 LuCI Feed 同名**符号链接**，避免重复注册。

继续启用 `CONFIG_PACKAGE_luci-mod-battstatus=y`、`CONFIG_PACKAGE_luci-i18n-battstatus-zh-cn=y`。原先 `files/www/luci-static/resources/preload/battstatus.js` 已取消，由本插件自行打包 JS。

需要调整界面时，直接修改本目录的 `htdocs/luci-static/resources/preload/battstatus.js`；无需 Python 修复脚本，也不必修改 Aurora 主题。插件本地副本不会自动跟进官方更新；新结构尚未实际编译及真机测试。
