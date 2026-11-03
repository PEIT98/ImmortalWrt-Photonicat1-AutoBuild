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
| [fix-qmodem-usb-net-filter.py](patches/fix-qmodem-usb-net-filter.py) | 将 USB 网卡识别前置，收集后跳过端口限制，再按原规则处理 AT 串口和语音端口；无需逐型号补接口 |
| [fix-qmodem-boot-scan.py](patches/fix-qmodem-boot-scan.py) | 使官方延时补扫遵从 USB/PCIe 开关，关闭自动扫描时不额外扫描 |
| [wifi-band-order.sh](patches/wifi-band-order.sh) | 板载 SDIO 优先 2.4GHz，M.2 等其他网卡优先 5GHz，按网卡频段能力回退；统一 SSID Photonicat-Wrt，WPA2-PSK，密码 photonicat |

## 光影猫电池与电源插件

- [luci-app-photonicat-power](../packages/luci-app-photonicat-power/) 包含 [battstatus.js](../packages/luci-app-photonicat-power/htdocs/luci-static/resources/preload/battstatus.js)、电源管理页面、两个 RPC 服务、MCU 守护进程、ACL 和电池翻译源码；固件内只安装这个插件。
- 编译时由 `build/prepare.sh` 复制整个本地包，并移除 Feeds 的同名电池插件链接。简体中文翻译随包安装，无需额外选择翻译包。
- 不再需要 `fix-aurora-battstatus.py` 或 `files/www/` 静态覆盖，**不修改 Aurora 主题源码**。

## 项目内置的 LuCI 插件

- [电池与电源管理](../packages/luci-app-photonicat-power/README.md)：电量卡片、顶部显示开关、低电量提醒、UPS 倒计时和 PMU 后台；显示设置保存到独立 UCI 配置。
- [CPU 调频管理 luci-app-cpufreq](../packages/luci-app-cpufreq/README.md)：整个插件直接存放在项目内；可修改网页、菜单、权限及简体中文翻译。后台仍采用官方 `cpufreq`，无需另外的修改脚本。
- [在线升级 luci-app-online-upgrade](../packages/luci-app-online-upgrade/README.md)：SWRT 更新器适配本仓库，包含独立网页、后台、配置、菜单和权限，支持正式/预发行通道及国内/GitHub 源。
- 编译时 `build/prepare.sh` 复制本地源码；随后移除 Feeds 中同名符号链接以避免重复注册。

## 配置来源与构建顺序

1. `build/prepare.sh` 继承参考设备配置，并加载兼容补丁。
2. 更新 Feeds 后，应用并回归 QModem USB 网卡扫描补丁，再由 `build/select-packages.py` 应用根目录 `photonicat1.config` 的覆盖项。
3. 运行 `make defconfig`，再由 `build/verify-config.sh` 检查依赖。
4. 编译成功后用 `build/release-notes.sh` 生成发布说明。

**配置文件区别：** `photonicat1.config` 只保存需要覆盖的配置；完整 `immortalwrt/.config` 在编译期间生成，并上传至 Actions 的 `photonicat1-build-config` Artifact。无需将旧版完整配置拷入仓库。

**编译触发：** 仅通过 Actions 手动 `Run workflow` 编译。保留所有插件、系统配置、源码缓存及 CCache。

**品牌和网络默认值：** 主机名及 5GHz／2.4GHz Wi-Fi 名称均为 `Photonicat-Wrt`；后台 [http://172.16.0.1](http://172.16.0.1/)；后台 root 密码与 Wi-Fi 密码均为 `photonicat`。板载 SDIO 优先 2.4GHz，M.2 等其他网卡优先 5GHz（支持时 AX／80MHz／36 信道）；实际频段由网卡能力决定。完整默认值见[主说明](../README.md#默认网络设置)。

`photonicat1.config` 设置固件品牌，Aurora 无需改源码；[首启配置](../files/etc/uci-defaults/99-photonicat-brand) 迁移原默认主机名，并仅在 root 密码为空时初始化密码。这些默认值需要重新编译；保留配置升级时沿用已有网络、无线、root 密码和自定义主机名。

**QModem 菜单名称：** [独立菜单文件](../files/usr/share/luci/menu.d/zz-photonicat-modem-title.json) 仅覆盖 `admin/modem` 的标题为“移动网络”。LuCI 按顺序合并菜单，原有子页面、动作和 ACL 保留。

**QModem 与 Generic：** `build/prepare.sh` 注册官方 [FUjr/QModem](https://github.com/FUjr/QModem) `main` 和 [PEIT98/luci-app-qmodem-generic](https://github.com/PEIT98/luci-app-qmodem-generic) `main` 两个软件源，由 Feeds 递归安装。Generic 原样复刻自 LianXia233，后续 WebUI 修复直接在自有仓库维护。Actions 检查依赖、菜单和安装文件冲突，构建信息记录两个源的实际提交号。参考仓库针对 ImmortalWrt `master` 的 `input-support` 门控未照搬到本项目 `openwrt-25.12`。

**QModem 开机识别：** [有限启动检查](../files/usr/bin/photonicat-qmodem-scan)在实际 USB 网卡和同设备串口出现后补充扫描，最多检查 36 轮；识别成功即退出，持续失败且没有已识别模组时最多恢复一次扫描服务。已有配置及关闭扫描的选择保留，不写死槽位、AT 口和网卡名，不要求安装 `timeout`。独立的首启迁移标记使旧固件升级也能启用此服务。执行 `python3 scripts/tests/test_qmodem_boot_scan.py` 验证晚到端口、异步去重、恢复边界、单次恢复、并发锁及旧配置迁移；Actions 在固件编译前执行同一测试。

**在线升级：** `build/prepare.sh` 将项目内完整 [luci-app-online-upgrade](../packages/luci-app-online-upgrade/) 复制到 `package/luci-app-online-upgrade`，光影猫适配直接在插件源码中维护。Actions 核对整套源码复制一致，并将同一个 Release 标签写进固件身份和发布任务；检查版本时优先读取 `/rom` 中本次固件的身份，避免旧配置覆盖版本记录。固件及 Release 的来源信息记录本项目提交号。

**管理工具：** 文件管理、Travelmate 和 SQM 来自官方软件源；Aurora 设置直接拉取主题作者 `master`，保留上游关闭旧 jsmin 的设置并记录实际提交号。[首次配置](../files/etc/uci-defaults/92-photonicat-network-tools) 将 Travelmate 关联 `wwan` 并保持关闭。

**cake-autorate：** [本地包](../packages/cake-autorate/README.md) 固定稳定版提交和下载 SHA256，原样安装上游核心，首次关闭。启动前检查实际 QModem/mwan3 接口、SQM 和真实 CAKE/IFB 队列，探测固定走选定出口。网络事件会刷新实际接口，缺少队列时不启动；原有网络、防火墙和 SQM 配置由用户维护。

## eMMC 与 USB 存储

- `patches/enable-emmc-autogrow.py`：检查 Rockchip 的镜像校验及刷写流程，保留扩大的根分区；上游无关注释变化不阻断构建，受影响逻辑变化时停止并提示核对。
- `files/usr/libexec/swrt-autogrow` 与 `files/lib/preinit/79-swrt-autogrow`：在 overlay 挂载前扩展 eMMC 的连续可用空间。
- `build/stamp-firmware.py`：验证并写入在线更新使用的不可变版本身份。
- `packages/luci-app-swrt-disk-keepalive`：完整本地 USB 硬盘保活插件，默认关闭。
- `tests/test_autogrow.py`、`tests/test_storage_integration.py`：验证分区比较、生产扩容计划、额外分区保护和依赖。
- `tests/test_autogrow_real.py`：在临时稀疏磁盘与 loop 设备上验证 F2FS/ext4 扩容；需要 Linux root、相关工具和内核支持。
- `tests/test_disk_keepalive.py`：验证硬盘标识和直接读取；没有 loop 设备时仍运行不接触真实磁盘的识别测试。

存储组件来源：SlAlot/ImmortalWrt_Photonicat1 `ae655185`，AGPL-3.0-only。移植保持现有网络、电源与 Docker 配置。

**软件包镜像设置：** `luci-app-photonicat-power` 内置 `photonicat-package-source` 与 `package-sources.awk`，由同页独立 RPC 管理。首启脚本 `99-photonicat-package-source` 默认应用南京大学镜像，并在保留配置升级后重用用户选择。`tests/test_package_sources.py` 与前端测试覆盖源路径保留、权限、失败恢复和 MCU 离线场景。

**构建依赖兼容：** `patches/fix-weechat-provider.py` 将 WeeChat 的虚拟依赖落实为已有的默认 `weechat-minimal` 提供者，避免 Kconfig 自递归，不额外启用该插件。自动扩容使用明确选中的 `coreutils-od` 读取文件系统头，不依赖默认配置中隐藏的 BusyBox 选项。配置解析日志保存在 `photonicat-defconfig.log`，发现递归错误时立即停止。
