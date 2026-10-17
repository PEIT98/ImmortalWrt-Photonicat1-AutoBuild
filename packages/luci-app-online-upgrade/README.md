# 光影猫一代在线升级插件

入口：**系统 → 在线升级**。完整源码放在本目录，构建时由 `scripts/build/prepare.sh` 复制到 ImmortalWrt 的 `package/luci-app-online-upgrade`。

基于 [gooyjq/luci-app-online-upgrade](https://github.com/gooyjq/luci-app-online-upgrade/tree/6f587f19d7f884ca89e4bfa95bbb9a002a521477) 提交 `6f587f19d7f884ca89e4bfa95bbb9a002a521477`，保留上游许可证与源码，已将光影猫适配合入插件。以后直接修改此目录；构建使用本地版本，来源信息记录本项目提交号。

- `Makefile`：安装规则及 LuCI、curl、jq、SHA256、flock 等依赖。
- `root/www/luci-static/resources/view/system/online-upgrade.js`：网页设置、版本检查、真实任务进度及升级入口。
- `root/usr/bin/online-upgrade.sh`：发布识别、固件下载、完整性与机型校验、备份及升级。
- `root/etc/config/online-upgrade`：默认仓库、下载加速、保留配置等设置。
- `root/etc/uci-defaults/`：首次启动配置及旧默认设置迁移。
- `root/usr/share/luci/menu.d/`、`root/usr/share/rpcd/acl.d/`：LuCI 菜单及权限。
- `root/lib/upgrade/keep.d/online-upgrade`：保留插件配置。
- `po/`：上游翻译源码；当前主页面直接使用中文。

默认检查 `PEIT98/ImmortalWrt-Photonicat1-AutoBuild` 的最新正式发布，只匹配光影猫一代 squashfs sysupgrade 镜像。下载后依次检查文件大小、gzip 格式、SHA256 和 `sysupgrade -T`，默认备份并保留配置。下载加速失败或文件校验失败时回退 GitHub 原地址；加速地址可留空直连。

只在手动确认后升级。恢复备份使用 LuCI 自带的“备份与升级”页面。固件身份由 Actions 写入 `/etc/online-upgrade-device`，检查时优先读取 `/rom` 中的本次固件身份。

检查方式（在项目根目录执行）：

```sh
python3 scripts/tests/test_online_upgrade.py
node scripts/tests/test_online_upgrade_frontend.js packages/luci-app-online-upgrade/root/www/luci-static/resources/view/system/online-upgrade.js
```

以上为隔离环境测试，实际升级流程仍需编译并刷入固件后在设备上验证。
