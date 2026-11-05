# 构建脚本（中文功能说明）

项目自有构建、补丁和回归脚本统一使用 Shell：生产补丁用 `sh`，主机测试用 `bash`；文本与 JSON 处理使用 `awk`、`sed`、`jq` 和系统工具。ImmortalWrt 上游工具链仍需 Python，构建环境依赖保留。

此目录按 **构建管理** 和 **兼容补丁** 分类。脚本保持英文文件名以兼容 Linux 路径和 GitHub Actions。

## build：构建管理

| 脚本 | 作用 |
| --- | --- |
| [prepare.sh](build/prepare.sh) | 继承光影猫参考配置，准备软件源、内核补丁和覆盖文件；内部函数负责替换默认 MCU 包，并隔离临时文件清理 |
| [select-packages.sh](build/select-packages.sh) | 在安装 Feeds 后读取独立配置，选择插件和驱动 |
| [verify-config.sh](build/verify-config.sh) | 检查目标设备、插件、驱动和依赖；缺少必要配置则停止 |
| [release-notes.sh](build/release-notes.sh) | 生成 GitHub Release 中文说明和编译来源信息 |
| [bundle-nfa765-e108.sh](build/bundle-nfa765-e108.sh) | 校验并内置 hw2.1 E108 专用 amss/m3 和板卡文件，只对 `105b:e108` 选择私有目录，保留普通 NFA765 默认固件 |

## patches：兼容补丁

| 脚本 | 作用 |
| --- | --- |
| [enable-qca9377-ath10k-sdio.sh](patches/enable-qca9377-ath10k-sdio.sh) | 保留 PCIe ath10k，同时为板载 QCA9377 加入 SDIO 驱动 |
| [fix-istore-25.12.sh](patches/fix-istore-25.12.sh) | 检查 taskd 等依赖，在临时副本中校验并固定 iStore 包名，通过后写回 |
| [fix-qmodem-ndisc6-source.sh](patches/fix-qmodem-ndisc6-source.sh) | 仅处理 ndisc6 源码下载和编译兼容，保留官方 QM 扫描及拨号源码 |
| [wifi-band-order.sh](patches/wifi-band-order.sh) | 板载 SDIO 优先 2.4GHz，M.2 等其他网卡优先 5GHz，按网卡频段能力回退；统一 SSID Photonicat-Wrt，WPA2-PSK，密码 photonicat |

## 光影猫电池与电源插件

- [luci-app-photonicat-power](../packages/luci-app-photonicat-power/) 包含 [battstatus.js](../packages/luci-app-photonicat-power/htdocs/luci-static/resources/preload/battstatus.js)、电源管理页面、两个 RPC 服务、MCU 守护进程、ACL 和电池翻译源码；固件内只安装这个插件。
- 编译时由 `build/prepare.sh` 复制整个本地包，并移除 Feeds 的同名电池插件链接。简体中文翻译随包安装，无需额外选择翻译包。
- 电池状态由本地插件提供，**不修改 Aurora 主题源码**。

## 项目内置的 LuCI 插件

- [电池与电源管理](../packages/luci-app-photonicat-power/README.md)：电量卡片、顶部显示开关、低电量提醒、UPS 倒计时和 PMU 后台；显示设置保存到独立 UCI 配置。
- [CPU 调频管理 luci-app-cpufreq](../packages/luci-app-cpufreq/README.md)：整个插件直接存放在项目内；可修改网页、菜单、权限及简体中文翻译。后台仍采用官方 `cpufreq`，无需另外的修改脚本。
- [在线升级 luci-app-online-upgrade](../packages/luci-app-online-upgrade/README.md)：SWRT 更新器适配本仓库，包含独立网页、后台、配置、菜单和权限，支持正式/预发行通道及国内/GitHub 源。
- 编译时 `build/prepare.sh` 复制本地源码；随后移除 Feeds 中同名符号链接以避免重复注册。

## 配置来源与构建顺序

1. `build/prepare.sh` 继承参考设备配置，并加载兼容补丁。
2. 更新 Feeds 后，核对官方 QModem 运行源码保持原样，再由 `build/select-packages.sh` 应用根目录 `photonicat1.config` 的覆盖项。
3. 运行 `make defconfig`，再由 `build/verify-config.sh` 检查依赖。
4. 编译成功后用 `build/release-notes.sh` 生成发布说明。

**配置文件区别：** `photonicat1.config` 只保存需要覆盖的配置；完整 `immortalwrt/.config` 在编译期间生成，并上传至 Actions 的 `photonicat1-build-config` Artifact。无需将旧版完整配置拷入仓库。

**编译触发：** 仅通过 Actions 手动 `Run workflow` 编译。保留所有插件、系统配置、源码缓存及 CCache。

**品牌和网络默认值：** 主机名及 5GHz／2.4GHz Wi-Fi 名称均为 `Photonicat-Wrt`；后台 [http://172.16.0.1](http://172.16.0.1/)；后台 root 密码与 Wi-Fi 密码均为 `photonicat`。板载 SDIO 优先 2.4GHz，M.2 等其他网卡优先 5GHz（支持时 AX／80MHz／36 信道）；实际频段由网卡能力决定。完整默认值见[主说明](../README.md#默认网络设置)。

`photonicat1.config` 设置固件品牌，Aurora 无需改源码；[首启配置](../files/etc/uci-defaults/99-photonicat-brand) 迁移原默认主机名，并仅在 root 密码为空时初始化密码。这些默认值需要重新编译；保留配置升级时沿用已有网络、无线、root 密码和自定义主机名。

**QModem 菜单名称：** [独立菜单文件](../files/usr/share/luci/menu.d/zz-photonicat-modem-title.json) 仅覆盖 `admin/modem` 的标题为“移动网络”。LuCI 按顺序合并菜单，原有子页面、动作和 ACL 保留。

**QModem 与 Generic：** `build/prepare.sh` 注册官方 [FUjr/QModem](https://github.com/FUjr/QModem) `main` 和 [PEIT98/luci-app-qmodem-generic](https://github.com/PEIT98/luci-app-qmodem-generic) `main` 两个软件源，由 Feeds 递归安装。Generic 原样复刻自 LianXia233，后续 WebUI 修复直接在自有仓库维护。Actions 检查依赖、菜单和安装文件冲突，构建信息记录两个源的实际提交号。参考仓库针对 ImmortalWrt `master` 的 `input-support` 门控未照搬到本项目 `openwrt-25.12`。

**网络默认值：** QM 不附加首启恢复、补扫、USB/AT 排序或接口同步脚本，配置与 LuCI 权限均随官方 QM 和 Generic 安装。mwan3 使用上游默认配置，[首启文件](../files/etc/uci-defaults/99-mwan3-disable)仅停止服务并关闭自启动。项目不预建无线中继接口、不改写防火墙。需要清除设备上的旧 APN、串口及网络设置时，刷机请选择不保留配置。

**QModem 源码与驱动：** `build/verify-qmodem-feeds.sh runtime` 检查扫描、AT 端口、拨号、连接管理器和驱动目录与官方提交一致；仅 ndisc6 有构建兼容修复。QMI 选择项恢复为上游默认的厂商驱动，依赖检查同步核对移远、广和通和芯讯通三个驱动包。

**TD-TECH 串口支持：** [原版内核补丁](../999-add-TD-TECH-option-id.patch)由 `build/prepare.sh` 复制到 Rockchip Linux 6.12 补丁目录，为 `3466` 的指定 USB 接口增加 `option` 驱动匹配，不改 QM 端口排序、扫描或拨号代码。

**在线升级：** `build/prepare.sh` 将项目内完整 [luci-app-online-upgrade](../packages/luci-app-online-upgrade/) 复制到 `package/luci-app-online-upgrade`，光影猫适配直接在插件源码中维护。Actions 核对整套源码复制一致，并将同一个 Release 标签写进固件身份和发布任务；检查版本时优先读取 `/rom` 中本次固件的身份，避免旧配置覆盖版本记录。固件及 Release 的来源信息记录本项目提交号。

**管理工具：** 文件管理、Travelmate 和 SQM 来自官方软件源并使用上游默认配置；Aurora 设置直接拉取主题作者 `master`，保留上游关闭旧 jsmin 的设置并记录实际提交号。

## eMMC 与 USB 存储

- `patches/enable-emmc-autogrow.sh`：检查 Rockchip 的镜像校验及刷写流程，保留扩大的根分区；上游无关注释变化不阻断构建，受影响逻辑变化时停止并提示核对。
- `files/usr/libexec/swrt-autogrow` 与 `files/lib/preinit/79-swrt-autogrow`：在 overlay 挂载前扩展 eMMC 的连续可用空间。
- `build/stamp-firmware.sh`：统一校验并生成 `photonicat-release.json` 和 `online-upgrade-device`，两种版本身份共用同一设备、标签和提交号。
- `packages/luci-app-swrt-disk-keepalive`：完整本地 USB 硬盘保活插件，默认关闭。
- `tests/test_autogrow.sh`、`tests/test_storage_integration.sh`：验证分区比较、生产扩容计划、额外分区保护和依赖。
- `tests/test_autogrow_real.sh`：在临时稀疏磁盘与 loop 设备上验证 F2FS/ext4 扩容；需要 Linux root、相关工具和内核支持。
- `tests/test_disk_keepalive.sh`：验证硬盘标识和直接读取；没有 loop 设备时仍运行不接触真实磁盘的识别测试。

存储组件来源：SlAlot/ImmortalWrt_Photonicat1 `ae655185`，AGPL-3.0-only。移植保持现有网络、电源与 Docker 配置。

**软件包镜像设置：** `luci-app-photonicat-power` 内置 `photonicat-package-source` 与 `package-sources.awk`，由同页独立 RPC 管理，支持南京大学、中科大、上海交大、浙江大学、VSEAN 和官方源。识别系统中文默认的 VSEAN，读取失败可在页面刷新重试；未知自定义源仅禁止保存，不锁住下拉列表。首启脚本 `99-photonicat-package-source` 默认应用南京大学镜像，并在保留配置升级后重用用户选择。`tests/test_package_sources.sh` 与前端测试覆盖镜像轮换、域名别名、路径保留、权限、失败恢复、状态重试和 MCU 离线场景。

**构建依赖兼容：** `patches/fix-weechat-provider.sh` 将 WeeChat 的虚拟依赖落实为已有的默认 `weechat-minimal` 提供者，避免 Kconfig 自递归，不额外启用该插件。自动扩容使用明确选中的 `coreutils-od` 读取文件系统头，不依赖默认配置中隐藏的 BusyBox 选项。配置解析日志保存在 `photonicat-defconfig.log`，发现递归错误时立即停止。
