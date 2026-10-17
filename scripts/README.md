# 构建脚本（中文功能说明）

此目录按 **构建管理** 和 **兼容补丁** 分类。脚本保持英文文件名以兼容 Linux 路径和 GitHub Actions。

## build：构建管理

| 脚本 | 作用 |
| --- | --- |
| [prepare.sh](build/prepare.sh) | 继承光影猫参考配置，准备软件源、内核补丁和覆盖文件 |
| [select-packages.py](build/select-packages.py) | 在安装 Feeds 后读取独立配置，选择插件和驱动 |
| [verify-config.sh](build/verify-config.sh) | 检查目标设备、插件、驱动和依赖；缺少必要配置则停止 |
| [release-notes.sh](build/release-notes.sh) | 生成 GitHub Release 中文说明和编译来源信息 |

## patches：兼容补丁

| 脚本 | 作用 |
| --- | --- |
| [enable-qca9377-ath10k-sdio.py](patches/enable-qca9377-ath10k-sdio.py) | 保留 PCIe ath10k，同时为板载 QCA9377 加入 SDIO 驱动 |
| [fix-istore-25.12.sh](patches/fix-istore-25.12.sh) | 修复 iStore 包名与 taskd 依赖检查 |
| [wifi-band-order.sh](patches/wifi-band-order.sh) | 使用上游 Wi-Fi 脚本并调整频段显示顺序 |

## 电池指示插件（直接集成）

- 完整的 [luci-mod-battstatus](../packages/luci-mod-battstatus/) 直接放入项目，包含 [battstatus.js](../packages/luci-mod-battstatus/htdocs/luci-static/resources/preload/battstatus.js)、原版电池 RPC、ACL 和全部上游翻译。
- 编译时由 `build/prepare.sh` 将本地插件复制进 `package/`，随后移除 Feeds 的同名符号链接。
- 不再需要 `fix-aurora-battstatus.py` 或 `files/www/` 静态覆盖，**不修改 Aurora 主题源码**。

## 项目内置的 LuCI 插件

- [电池状态 luci-mod-battstatus](../packages/luci-mod-battstatus/README.md)：整套插件源码内置，含 Aurora 电池显示修改、RPC 及翻译。
- [电池与电源管理](../packages/luci-app-photonicat-power/README.md)：电量卡片、顶部显示开关、低电量提醒和 UPS 倒计时；显示设置保存到独立 UCI 配置。
- [CPU 调频管理 luci-app-cpufreq](../packages/luci-app-cpufreq/README.md)：整个插件直接存放在项目内；可修改网页、菜单、权限及简体中文翻译。后台仍采用官方 `cpufreq`，无需另外的修改脚本。
- [在线升级 luci-app-online-upgrade](../packages/luci-app-online-upgrade/README.md)：整套网页、后端、配置、菜单、权限及上游翻译存放在插件目录内，已包含光影猫固件识别和升级校验。
- 编译时 `build/prepare.sh` 复制本地源码；随后移除 Feeds 中同名符号链接以避免重复注册。

## 配置来源与构建顺序

1. `build/prepare.sh` 继承参考设备配置，并加载兼容补丁。
2. 更新 Feeds 后，`build/select-packages.py` 应用根目录 `photonicat1.config` 的覆盖项。
3. 运行 `make defconfig`，再由 `build/verify-config.sh` 检查依赖。
4. 编译成功后用 `build/release-notes.sh` 生成发布说明。

**配置文件区别：** `photonicat1.config` 只保存需要覆盖的配置；完整 `immortalwrt/.config` 在编译期间生成，并上传至 Actions 的 `photonicat1-build-config` Artifact。无需将旧版完整配置拷入仓库。

**编译触发：** 仅通过 Actions 手动 `Run workflow` 编译。保留所有插件、系统配置、源码缓存及 CCache。

**QModem 菜单名称：** [独立菜单文件](../files/usr/share/luci/menu.d/zz-photonicat-modem-title.json) 仅覆盖 `admin/modem` 的标题为“移动网络”。LuCI 按顺序合并菜单，原有子页面、动作和 ACL 保留。

**QModem 与 Generic：** `build/prepare.sh` 注册官方 [FUjr/QModem](https://github.com/FUjr/QModem) `main` 和 [luci-app-qmodem-generic](https://github.com/LianXia233/luci-app-qmodem-generic) `main` 两个软件源，由 Feeds 递归安装；不将插件源码复制到项目内。Actions 检查依赖、菜单和安装文件冲突，构建信息记录两个源的实际提交号。参考仓库针对 ImmortalWrt `master` 的 `input-support` 门控未照搬到本项目 `openwrt-25.12`。

**在线升级：** `build/prepare.sh` 将项目内完整 [luci-app-online-upgrade](../packages/luci-app-online-upgrade/) 复制到 `package/luci-app-online-upgrade`，光影猫适配直接在插件源码中维护。Actions 核对整套源码复制一致，并将同一个 Release 标签写进固件身份和发布任务；检查版本时优先读取 `/rom` 中本次固件的身份，避免旧配置覆盖版本记录。固件及 Release 的来源信息记录本项目提交号。
