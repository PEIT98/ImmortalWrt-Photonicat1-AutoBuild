# 光影猫一代 Photonicat-Wrt 自动编译

**Photonicat-Wrt** 是基于 **ImmortalWrt 25.12** 的光影猫一代固件，适用于 **Ariaboard Photonicat 一代（RK3568）**。

- 固件源码：[ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `openwrt-25.12`
- 设备参考：[光影猫一代](https://github.com/a757814283/ImmortalWrt_Photonicat1)
- 5G 模组管理：[官方 FUjr/QModem](https://github.com/FUjr/QModem) `main`（Next + 短信后台），另加 [PEIT98/QModem Generic](https://github.com/PEIT98/luci-app-qmodem-generic) `main`（复刻自 [LianXia233](https://github.com/LianXia233/luci-app-qmodem-generic)）

## 主要功能

| 分类 | 内置功能 |
| --- | --- |
| 5G / 网络 | QModem Next（含短信）、QModem Generic、mwan3、OpenClash、Travelmate 无线中继、SQM/CAKE 与 cake-autorate |
| 系统界面 | Aurora 主题及设置、右上角模组/网口/无线/电池状态、光影猫一代管理（电源控制实验性）、CPU 调频、ttyd 网页终端、固件信息卡片 |
| 应用与容器 | iStore、Docker、Docker Compose、Dockerman |
| 管理工具 | 文件管理、历史统计、在线升级、DiskMan、Bandix Plus、定时重启、UPnP |
| 诊断工具 | `lsusb`、`lspci`、`lsblk`、`iperf3`、`tcpdump` |
| 驱动支持 | USB QMI / MBIM / ECM / NCM / RNDIS、AT 串口、PCIe / SDIO 无线网卡 |

无线驱动包括 Realtek RTL8922AE / RTL8852BE / RTL8852CE、MediaTek MT7921 / MT7925 / MT7916、Qualcomm ath10k / ath11k / ath12k。板载 QCA9377 系列使用 SDIO 驱动，是否可用取决于板子实际硬件和固件支持。内置 [TD-TECH 3466 USB 串口补丁](999-add-TD-TECH-option-id.patch)。

**默认设置：** Bandix Plus 流量功能不开启；Docker 存储检测仅显示信息，不执行挂载、迁移或格式化。固件仅生成 **squashfs sysupgrade** 镜像，不生成 ext4 镜像；`kmod-fs-ext4` 仍保留，支持 ext4 硬盘或 U 盘。

每次手动编译会从 OpenClash 官方 `core` 分支获取当时最新的稳定版 **Meta linux-arm64 内核**，按官方 SHA256 清单校验并内置。新固件首次启动（包括保留配置升级）会接入内置内核，无需在 OpenClash 页面另行下载；Smart、Oix、开发版以及手动启用的小闪存模式仍按 OpenClash 原流程处理。已运行的固件不会因此自动更新，需编译并刷入新固件。

## 默认网络设置

以下为当前 `main` 分支的默认值，需重新编译并生成无线配置后生效。历史 Release 下载文件使用各自构建时的配置。

| 首次刷入／恢复出厂设置 | 默认值 |
| --- | --- |
| 主机名及界面品牌 | `Photonicat-Wrt` |
| 后台地址 | `http://172.16.0.1`（LAN：`172.16.0.1/24`） |
| 后台／SSH 账号及密码 | `root`／`photonicat` |
| 5GHz／2.4GHz Wi-Fi 名称 | 均为 `Photonicat-Wrt` |
| 频段判断顺序 | 优先 5GHz，其次 2.4GHz |
| 5 GHz 模式／带宽／信道 | AX（HE80）／80MHz／36；不支持 AX 或 80MHz 的网卡按硬件能力回退 |
| Wi-Fi 密码／加密 | `photonicat`／WPA2-PSK |

Wi-Fi 按检测到的实际频段生成，同一射频优先判断 5GHz，其次 2.4GHz，不固定网卡编号。保留配置升级时，已有 LAN 地址、无线设置、root 密码和自定义主机名继续保留；原默认主机名 `ImmortalWrt`／`OpenWrt` 会迁移为 `Photonicat-Wrt`。固件信息及页脚使用新品牌，登录页、左侧名称和浏览器标题跟随主机名；软件源和设备兼容标识保持原配置。root 默认密码只在账号尚未设置密码时初始化，由系统 `passwd` 生成并保存哈希。

无实时时钟、尚未联网时，固件开机将过旧的系统时间初始化到**镜像编译开始时间＋2小时**；已经正确的时间不会回退或覆盖。联网后仍由 NTP 同步准确时间。此设置只解决过旧时间造成的证书／联网问题，不能保证 QModem 一定识别模组。

## CPU 调频插件

已将完整 [luci-app-cpufreq](packages/luci-app-cpufreq/) 放入项目，包含网页设置、LuCI 菜单、RPC 权限与中文翻译。构建时优先使用本地源码，避免 Feeds 同名插件冲突；实际 CPU 调频服务依然使用官方 `cpufreq` 包。以后可直接编辑项目中的插件源码，不必新增修复脚本。

## 光影猫管理与顶部状态

现在只需一个软件包：[luci-app-photonicat-power](packages/luci-app-photonicat-power/)。其中同时包含 Aurora 顶部设备状态、系统 → 光影猫管理页面、简体中文翻译和 PMU-only MCU 后台。顶部依次显示 QModem 拨号状态对应的 4G/5G 与 RSRP 阶梯信号、WAN/LAN 两个网口、已加载的各个 Wi-Fi 射频、电池模式和电量；不显示模组名称，手机使用第二行可横向滚动。无线按内核 PHY 动态显示，双射频卡会出现两个图标。后台是 `/dev/ttyS4` 的唯一访问者，不依赖旧 Go FUSE。

电池页可保存右上角显示开关、低电量提醒及阈值（默认 20%），点击顶部电量可直接进入。新增手机电量卡片及 UPS 自动倒计时；显示设置重启保留，低电量提醒仅在打开路由器后台时生效。

已隔离官方 C 版的旧 5G 模组 GPIO、拨号及路由自动检查，不影响现有 QModem/mwan3 功能。新后台首次启用尚未完成真机测试，请先做好固件备份及恢复准备。

## 光影猫一代管理（电源控制实验性）

系统 → 光影猫管理支持手动、车载/UPS 延时关机、每日定时开关机。插件中的页面按官方 [pcat-manager v1 协议](https://github.com/photonicat/rockchip_rk3568_pcat_manager/tree/v1) 使用控制 Socket，不直接操作 MCU 串口。内置官方 v1 C 版 PMU-only 后台替代原 Go 版 pcat-mgr，通过 `/tmp/pcat-manager.sock` 获取电量及电源模式；需要重新编译刷机验证。具体限制见插件 README。

## 配置与脚本说明

- [构建脚本分类及中文说明](scripts/README.md)：查看所有编译管理和兼容补丁脚本。
- `photonicat1.config` 保存覆盖选项；编译时生成的完整 `.config` 在 Actions 的 `photonicat1-build-config` Artifact 中提供。

## 配置管理与编译优化

- [`photonicat1.config`](photonicat1.config)：集中维护所有强制启用及明确禁用的插件、驱动和编译开关（不是完整的 OpenWrt `.config`）。
- [`scripts/build/prepare.sh`](scripts/build/prepare.sh)：继承原光影猫参考配置，准备 Feeds、补丁和系统文件；不覆盖现有网络设计。
- [`scripts/build/select-packages.py`](scripts/build/select-packages.py)：在 Feeds 安装后应用上述配置，继承未明确修改的选项。
- [`scripts/build/verify-config.sh`](scripts/build/verify-config.sh)：在 `make defconfig` 后校验必需插件和依赖；缺失则停止编译，防止静默丢包。
- 编译并行度最多 3 线程且不超过实际 CPU 数；保留源码下载缓存、1.5GB CCache 和失败时单线程诊断机制。

仅在 GitHub Actions 手动启动编译；普通提交不会触发编译。

QModem 顶部菜单显示为“移动网络”，使用 [独立 LuCI 菜单文件](files/usr/share/luci/menu.d/zz-photonicat-modem-title.json) 覆盖名称。每次构建通过 Feeds 拉取官方 QModem `main` 和 [PEIT98/Generic](https://github.com/PEIT98/luci-app-qmodem-generic) `main`。Generic 已原样复刻，后续 WebUI 修复在自有仓库维护。

QModem 首次启动默认开启 **USB 开机扫描**，并设置 **15 秒追加扫描**。通过[独立首启配置](files/etc/uci-defaults/zz-photonicat-qmodem-usb-scan)应用一次；之后可在 **移动网络 → QModem → QModem 设置** 调整，保留配置升级时不会重复覆盖。不固定 USB 槽位或模组别名，继续动态识别接口。

USB 网卡按已绑定的 ECM、RNDIS、NCM、QMI、MBIM 驱动识别，不受 AT 端口白名单限制；保留原有 AT 串口和语音端口筛选。构建时应用[兼容补丁](scripts/patches/fix-qmodem-usb-net-filter.py)，并执行真实扫描函数的回归检查，避免 RG520F-EB 的 ECM 接口 `1.10/1.11` 被过滤。

QModem Next 自带两个短信页面：**短信消息**用于收发、会话和历史记录；**SIM 卡短信**用于查看、删除卡内原始短信。它们属于同一个插件。`qmodem-smsd` 和 `sms-forwarder-next` 是新版 Next 的短信依赖。

Generic 位于 **移动网络 → 模组管理**，与官方 **QModem** 页面并列，共用同一套模组配置和拨号后台。先用官方页面完成扫描与拨号，避免同时从两个页面修改模组。Generic 原版自带缓存、流量采集、MT5700 SIM 初始化和支持库同步服务，也会随上游一并启用。

**试用限制：** 本次核对的 Generic `a5a2b41` 控制任务未统一传递 QModem `73d1839` 要求的模组配置节，AT、异步短信和流量定时清零参数也有差异；拨号、短信及其他修改操作先用官方 Next 页面。Generic 本地后台测试的服务停止与锁清理项目未全部通过，尚需真机验证。固件和 Release 会记录两个上游的实际提交号，便于排查和回退。

## 多 WAN 优先级

**主备优先级（从高到低）：第一，有线 WAN（`wan`）；第二，Wi-Fi 中继（`wwan`）；第三，QModem 5G/LTE（动态接口）。**

mwan3 使用数值越小优先级越高的 `metric`。QModem 的 IPv4 拨号接口由同步脚本自动识别，可能是 `6_1`、`6_2` 或自定义别名；更换模组、接口变化及重启后会尝试自动同步。无需手动设置固定接口名。

Wi-Fi 中继使用 `wwan` 接口；QModem 拨号接口由系统自动识别，无需手动指定接口名称。mwan3 自动按照有线 WAN、Wi-Fi、5G 的顺序进行故障切换。查看当前动态绑定和在线状态：

```sh
uci -q get mwan3.qmodem_priority3.interface
mwan3 status
```

## 在线升级

入口：**系统 → 在线升级**。完整 [luci-app-online-upgrade](packages/luci-app-online-upgrade/) 插件存放在项目内，包含网页、升级后端、默认配置、菜单、权限及上游翻译。基于 [gooyjq/luci-app-online-upgrade](https://github.com/gooyjq/luci-app-online-upgrade) 适配光影猫一代，构建时直接复制本地插件，后续修改在插件目录内完成。

- 默认从本仓库查找最新正式固件，只选择光影猫一代 squashfs 升级镜像。
- 与参考仓库使用相同下载加速地址，失败或文件校验不通过时回退 GitHub 原地址；加速地址留空即可直连。
- 下载后检查文件大小、压缩格式、SHA256 和系统机型兼容性；默认保留配置并在升级前备份。
- 页面进度来自实际任务状态。备份恢复使用 LuCI 自带页面，只在手动点击确认后执行固件升级。

需要重新编译并刷入包含此插件的固件，后续才可从页面在线更新。当前版本以固件内置标识为准，保留配置不会沿用旧的版本标识。

## 新增管理工具

- **系统 → 文件管理器**：官方 `luci-app-filemanager`，在浏览器中管理文件。
- **Aurora 设置**：使用 [主题作者的配置插件](https://github.com/eamonxg/luci-app-aurora-config)，支持配色、布局、背景、字体与快捷按钮。
- **统计**：官方 `luci-app-statistics`，首次使用 60 秒采样，开启温度与当前出口 Ping，数据放在 `/tmp/rrd`，重启后清空；升级时保留用户修改过的统计配置。
- **服务 → Travelmate**：官方无线热点管理，预关联现有 `wwan`，首次保持关闭。扫描并添加自己的热点后再启用；有线 → Wi-Fi → 5G 的 mwan3 优先级保持原配置。
- **cake-autorate + 网络 → SQM QoS**：稳定版 3.2.1，首次关闭。先按实测速率设置 SQM 的 CAKE 队列和六项带宽，再启动自动调整；跟随实际 QModem 接口，详见 [配置步骤](packages/cake-autorate/README.md)。

## 编译与下载

1. 打开 [GitHub Actions](https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/actions/workflows/build.yml)。
2. 选择 **Run workflow**，分支选 `main`，点击运行。
3. 编译完成后，从 [Releases](https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/releases) 下载固件；`publish=true` 时自动上传为 **预发布（Pre-release）**。

测试确认正常后，在对应 Release 的编辑页面取消“预发布”标记，保存为正式版本。在线升级只识别正式版本，预发布固件可手动下载测试。

**仅手动编译**，普通代码提交不会启动 Actions。构建使用源码下载缓存和 CCache；Release 附带 SHA256 校验、软件包清单和源码版本信息。sysupgrade 镜像文件名包含北京时间 `YYYYMMDDHH`。

刷机前请备份设备配置并准备恢复方案。编译成功不等于已经通过真机测试。

## 新增插件记录

仅在**新增插件**时更新此处；日常修复、配置调整和已不使用的功能不写历史记录。

- **2026-10-12**：Aurora 主题、ttyd 网页终端。
- **2026-10-13**：iStore、Docker / Docker Compose / Dockerman、Bandix Plus、DiskMan、定时重启、UPnP。
- **2026-10-15**：光影猫一代电源管理（实验性，仅连接兼容 MCU Socket）。
- **2026-10-17**：QModem Generic（引用 PEIT98 自有复刻仓库 `main`，与官方 QModem Next 共存）。
- **2026-10-17**：在线升级（完整本地插件，适配本仓库光影猫固件）。
- **2026-10-17**：文件管理、Aurora 设置、历史统计、Travelmate 无线中继、SQM/CAKE 与 cake-autorate。

其余插件和驱动以 [独立选包配置](photonicat1.config) 为准。
