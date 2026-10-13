# 光影猫一代 ImmortalWrt + QModem 自动编译

适用 **Ariaboard Photonicat 一代（RK3568）**，**不是光影猫二代**。已有 GitHub Actions 成功编译记录；但新增插件及不同镜像格式仍需分别通过下一次编译和真机验证。

## 源码组成

- **ImmortalWrt**：每次拉取 [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) 的 `openwrt-25.12` 分支最新源码。
- **光影猫一代原作者配置**：参考 [a757814283/ImmortalWrt_Photonicat1](https://github.com/a757814283/ImmortalWrt_Photonicat1) 中固定版本的 `.config` 和 feeds 配置；避免意外导入旧版静态 USB 拨号配置、Wi-Fi 凭据。
- **QModem**：每次从 [FUjr/QModem](https://github.com/FUjr/QModem) 的 `stable` 分支拉取最新稳定版，采用 `luci-app-qmodem-next`（含短信功能）。
- **自动编译方案**：参考 [西瓜皮 ImmortalWrt 自动构建](https://github.com/zzzz0317/immortalwrt-xgp-auto-build)，单独提供光影猫设备的编译工作流。

## 软件选择

| 项目 | 状态 |
|---|---|
| QModem / QModem Next（含短信） | 保留 |
| mwan3 多 WAN 路由及 LuCI | 保留 |
| 状态 → MultiWAN 管理器入口 | 移除（网络 → MultiWAN 配置菜单及后台 mwan3 保留） |
| luci-app-openclash | 保留 |
| luci-app-cpufreq | 保留 |
| luci-mod-battstatus | 保留 |
| luci-app-online-upgrade（光影猫专用完整版） | GitHub 更新检查、SHA256、分区校验、下载、一键升级、备份、保留/清空配置 |
| iStore 应用商店（luci-app-store） | 新增，使用 LinkEase 官方 main feed |
| Docker Engine / CLI / Compose + Dockerman 管理界面 | 新增，使用 ImmortalWrt 官方 feeds |
| ath11k PCI / WCN6855 固件、USB QMI / MBIM 等驱动 | 保留 |

## WAN 优先级

**有线 WAN（wan） > Wi-Fi 中继（wwan） > QModem 5G/LTE（wwan_5g）**

预置 `files/etc/config/mwan3` 作为 IPv4 故障切换策略。**初次启动必须手动完成：**

1. 在 LuCI 无线设置中为 Wi-Fi STA 填写自己的 SSID/密码，绑定网络 `wwan`。
2. 在 QModem 中扫描并设置模组，将 **Alias/别名** 设为 `wwan_5g`，配置 APN 并拨号。
3. 检查 WAN 防火墙区域、`mwan3` 在线状态和真正的主备切换。不要同时让原有 DHCP `usb0` 接口和 QModem 接管同一模组。

**注意**：QModem Next 和传统 `luci-app-qmodem` UI 不应同时选用；其单独的 `luci-app-qmodem-mwan` 依赖传统 UI，所以本工程采用通用 `luci-app-mwan3`。

## 手动编译

到 [Actions](../../actions/workflows/build.yml) → **Photonicat1 ImmortalWrt QModem Build** → **Run workflow**，选择 `publish=true`（默认）并运行。

## 编译触发方式

目前 **仅保留手动编译**：在 GitHub Actions 中点击 Run workflow。已关闭每周定时编译和 push 自动触发。

构建成功后：
- **Actions → Artifacts** 保存实际生效的 `.config` 和固件包。
- **Releases** 发布镜像、软件包清单、源码版本 `build-sources.txt` 和 `SHA256SUMS.txt`。

## 安全与兼容说明

本工程保留光影猫一代设备及原 `pcat-mgr` 软件包。若管理程序抢占 AT 口，须在真机定位冲突后修复。原参考仓库中的无线密码及固定 USB 拨号设置不会引入。刷机前务必备份原厂固件并准备救砖方式；**不要使用西瓜皮固件的刷写命令或磁盘路径**。

自动更新上游源码可能造成某次构建失败或功能变化；构建成功也不等于真机兼容测试完成。
## 编译可靠性优化（参考西瓜皮）

- 记录磁盘、内存和磁盘设备情况；清理 Actions 运行环境中的无关大文件。
- feeds 更新后执行 `./scripts/feeds install -a -f -p qmodem`，优先使用 QModem feed 软件包。
- `make defconfig` 前后打印消失的显式软件包选项，并逐项核查设备和驱动。
- 即使配置检查失败，也在 Actions Artifacts 上传实际生成的 `.config` 便于排错。
- 使用 `make -j2 V=0` 编译；失败后 `make -j1 V=s` 输出完整诊断日志。
- 固件包含 `/etc/photonicat1-build-info`；Release 附带最近25个 ImmortalWrt 提交、固件包清单和 SHA256。

**尚未验证的兼容事项：**

- 历史 Actions 运行在 `make defconfig` 后缺少 `CONFIG_PACKAGE_qmodem=y`。现已发现原脚本在 feeds 安装前应用配置，导致选项被重置，修复顺序后仍需新一轮编译验证。
- 原参考配置选用旧版 `luci-app-clash`，但所用 ImmortalWrt 25.12 feeds 不提供它。本仓库明确改用官方 `vernesong/OpenClash` 提供的 `luci-app-openclash`，仍需实际编译与真机验证兼容性。
- QModem 已调整为与西瓜皮相同的 `stable` 分支；ImmortalWrt 仍为 `openwrt-25.12`。stable 版的短信与拨号包依赖不同于 main，因此已同步调整配置校验。

不要把 GitHub Actions 编译成功等同于真机验证通过。

## 首次编译失败后的修复说明

2026-10-12 检查 Actions #38185529059 的 `.config.before-defconfig`，发现 `scripts/feeds install -a` 之后原先指定的 QModem、mwan3 与电池插件选项全部消失。根因是配置顺序不正确：必须在安装 feeds 后运行 `scripts/select-packages.py`，再执行 `make defconfig`。

原 `luci-app-clash` 无法在原有 ImmortalWrt 25.12 feeds 中找到，改用 [官方维护的 OpenClash](https://github.com/vernesong/OpenClash)，实际包名 `luci-app-openclash`，构建时跟随 `master` 分支。该插件与旧 `luci-app-clash` 并非同一款，请在真机核对需求。

## 2026-10-12：Rust 编译中断定位及修复

Actions #38186226012 的日志明确显示 GitHub Runner 剩余 98 MB 磁盘空间，紧接着 `package/feeds/packages/rust [host]` 编译失败，单线程重试随后中断。

实际配置文件中 `CONFIG_RUBY_ENABLE_YJIT=y`，而 OpenClash 依赖 Ruby，ImmortalWrt/packages `lang/ruby/Makefile` 明确规定 YJIT 为 Ruby 添加 `rust/host` 编译依赖，并且 ARM64 默认开启。现在在 `scripts/select-packages.py` 明确禁用 YJIT，`verify-config.sh` 也将校验禁用状态。

此外构建工作流增加对 CodeQL/无关 Docker 镜像的空间清理、下载后的磁盘检查，以及在编译失败且剩余磁盘不足 3GiB 时禁止重复全量编译。**这些修改还没有成功编译及真机验证。**

当前 Github Ubuntu Runner 的 `/mnt` 不是独立分区，因此不能直接照搬西瓜皮的 `easimon/maximize-build-space` 扩容步骤；盲目在同一文件系统建立 LVM 并不能真正增加容量。

## 2026-10-12：网页终端、Aurora 主题与 PCIe Wi-Fi 扩展

- 网页终端：`luci-app-ttyd` + `ttyd`；通过 LuCI 登录访问，需要保管好管理密码。
- [Aurora 官方主题](https://github.com/eamonxg/luci-theme-aurora)：从 `master` 编译 `luci-theme-aurora`；源码自带首启默认主题脚本，保持 Bootstrap 主题作为回退选择。
- Realtek：RTL8922AE、RTL8852BE、RTL8852CE，驱动为 `kmod-rtw89-8922ae`、`kmod-rtw89-8852be`、`kmod-rtw89-8852ce`，对应 firmware 由包依赖安装。
- MediaTek：MT7925 → `kmod-mt7925e`；MT7921/MT7922 → `kmod-mt7921e`；MT7916 → `kmod-mt7915e` + `kmod-mt7916-firmware`。MT7925/MT7922 firmware 随对应驱动依赖安装。
- Qualcomm：QCNFA765 → `kmod-ath11k-pci` + `ath11k-firmware-wcn6855`（已有）；QCNCM865/WCN7850 → `kmod-ath12k` + `ath12k-firmware-wcn7850`；mini PCIe QCA9880/9882 → `kmod-ath10k` + `ath10k-firmware-qca988x`。
- 型号后面的 x3/x4 表示网卡数量，驱动只需安装一次，不需要按网卡数量重复选择。
- 启用 `DRIVER_11AC_SUPPORT`、`DRIVER_11AX_SUPPORT`、`DRIVER_11BE_SUPPORT`，并参考西瓜皮的脚本调整 `/lib/wifi/mac80211.uc` 的频段默认排序为 2.4G→5G→6G→60G。该脚本仅影响首次无线配置生成时的排序，**不会开启热点，也不会解锁监管限制**。

**兼容提醒：** 有驱动且 `lspci` 识别不代表必然支持 AP。尤其 RTL8852BE/RTL8922AE、Wi-Fi 7 设备是否能在光影猫 ARM64 上开启热点，需要以 `iw list` / `iw phy` 的 Supported interface modes 为准。QCNFA765 的特定 board-2.bin 也可能需要另外适配。Wi-Fi 7 相关功能还取决于固件、`wpad` 和内核支持。

新增无线驱动及固件可能显著增大镜像体积和编译资源使用，首次刷入前请检查 flash/存储空间及救砖准备。

## GitHub Actions 编译缓存

缓存已从 2026-10-12 的 `photonicat-cache-v2` 工作流起启用：

- **源码下载**：`immortalwrt/dl`，按 UTC 月份生成缓存键。新的月份可以从旧月份恢复；在 `make download` 成功后立即保存，后续编译失败也能复用下载结果。
- **OpenWrt CCache**：`CONFIG_CCACHE=y`，缓存目录为 `immortalwrt/.ccache`，限制为 **1536 MiB**。每次恢复最近的同配置缓存；编译完成（包括失败时）尝试保存已产生的 C/C++ 对象。
- **保留原有磁盘空间保护**：不缓存整个 `build_dir` 或 `staging_dir`，避免缓存空间增长导致再次出现磁盘耗尽。
- **检查缓存命中**：打开 Actions 中的 `Restore downloaded source cache`、`Restore OpenWrt CCache`、`Report compiler cache` 和 Job Summary，查看源下载是否命中以及 CCache 命中次数。
- **首次编译**：没有已有缓存，通常不会加速；后续编译如果上游依赖或编译器未发生大的变化才可能加速。CCache **不能跳过所有链接、打包、内核和工具链构建**，不能保证每次 40 分钟。
- **容量**：缓存配额受 GitHub 仓库/账户设置约束，旧缓存可能被清理；如果被清理，下次将重新编译。

只对原工作流增加缓存步骤；QModem stable、Aurora、ttyd、Wi-Fi 驱动、每周五自动构建以及 Releases 发布保持不变。

## Aurora 主题电池状态显示兼容修复（2026-10-12）

光影猫一代的 `luci-mod-battstatus` 使用 `luci.battstatus` RPC 读取 `/sys/class/power_supply/pcat-battery` 和 `pcat-charger`，不修改该数据接口。

原 Aurora 顶部状态栏 `#indicators > span[data-indicator]` 设为 20px 图标及 `font-size:0`，而 `luci-mod-battstatus` 没有专用图标，因此电量文字不可见。原插件的 JS 还把 `${info.name}` 和 `${info.color}` 放在普通单引号字符串中，低于 30% 时可能触发错误。

**修复方法（更新）：** 工作流的 `Fix battery plugin indicator (Aurora theme unchanged)` 步骤只修改 `feeds/luci/modules/luci-mod-battstatus/htdocs/luci-static/resources/preload/battstatus.js`。在电池插件 JS 中修复 DOM 访问、显示 28px 蓝色电量标签，并由该插件运行时针对自身 `battery-*` 元素插入一条隐藏多余 `::before` 图标的样式规则。**完全不修改 Aurora 主题的源码、`main.css`、配置文件或编译后的主题包**，主题每次都保持官方上游原样。原来的 `scripts/aurora-battstatus.css` 已删除。

**验证：** 刷入新编译固件后，切换到 Aurora 主题，顶部状态栏应能直接显示充电状态和电量百分比；20% 以下为红色、21～30% 为黄色，31% 以上恢复普通文字颜色。如显示 `Need pcat-mgr`，属于底层电池节点缺失，应检查 `pcat-mgr`；如果旧主题正常但 Aurora 不显示，检查浏览器缓存与脚本加载报错。

**状态：** 代码已加入编译工作流，但仍需要最新固件构建与真机测试验证。之前已经发布的 Release 不会自动更新。

### Aurora 电池对齐样式（2026-10-12 增补）

根据你之前验证的 `fix-battery-align.sh`，电池插件在 Aurora 下将电池标签设为高度 **28px**、`padding: 0 10px`、`margin: 0 4px`、居中显示、12px 文字、6px 圆角、蓝色半透明背景与描边。所有样式都由电池插件运行时用 `style.setProperty(..., 'important')` 应用于自身标签；仅用于隐藏其多余图标的微型 `<style>` 也由电池插件创建。**Aurora 主题仓库和主题静态文件不修改**。同时保留电量低于 30% 时变色、恢复后清色及完整充电状态悬停提示。无需在路由器上执行临时脚本。


## MyOpenWrt tom_modem ACL（2026-10-12）

将终端手动添加的 `/usr/share/rpcd/acl.d/tom_modem.json` 放入仓库 `files/usr/share/rpcd/acl.d/tom_modem.json`，作为固件根文件系统覆盖文件内置。每次固件编译时由 `scripts/prepare.sh` 复制并检查 JSON 格式，**首次启动 rpcd 自动加载，无需执行 `service rpcd restart`**。

授权按原脚本保留 `/usr/bin/tom_modem`、`/bin/cat`、`/sbin/ifup`、`/sbin/ifdown`、`/usr/bin/lsusb`、`/etc/init.d/qmodem_network`、USB `speed` 节点读取和 `ubus file.exec`。这些是具有执行网络管理命令能力的 ACL 权限，请仅授予受信任的 LuCI 用户/会话；这项修改**不提供也不安装** `tom_modem` 或 MyOpenWrt APP 可执行程序，必须确保它们已由其他包提供。

**注意**：本次只添加文件和准备阶段校验，已在进行的 GitHub Actions 编译仍使用启动时的旧提交；下次构建才会包含该文件。

## iStore + Docker（2026-10-13）

- **iStore**：编译时通过 `src-git istore https://github.com/linkease/istore;main` 引入 LinkEase 官方软件源，选择 `luci-app-store`、`luci-compat`；相关 `taskd`、`luci-lib-taskd` 随依赖安装。支持新固件使用的 APK 包管理，但 iStore 仓库内可安装的第三方应用仍取决于版本、架构和依赖，**不保证所有 iStore 应用都能直接安装**。
- **Docker**：选择 `docker` 命令行、`dockerd` 引擎、`docker-compose` 和 LuCI `luci-app-dockerman` 管理界面；其余内核、网络和存储驱动由软件包依赖/Kconfig 选择。不会预先拉取任何 Docker 容器镜像。
- **编译检查**：`make defconfig` 后验证以上软件包及 iStore 任务服务是否仍保留；如果上游变化导致包无法选择，工作流会直接报错，避免发布缺插件的固件。
- **资源提醒**：Docker/Compose 引入 Go 编译和大量依赖，可能显著增加 GitHub Actions 耗时、磁盘使用量与固件体积。首次编译成功与真机运行仍需验证；不保证能在 6 小时 Actions 限时内完成。
- **运行存储**：Docker 镜像和容器应尽量放到空间足够的 ext4 外部存储/SSD 上，避免写满路由器系统 overlay。**本次不会自动分区、格式化磁盘、迁移 Docker data-root 或更改防火墙**。刷机后先检查磁盘挂载和 Docker 数据目录，再开始拉取镜像。
- **与现有功能关系**：不修改 Aurora 主题源码、独立电池修复、QModem stable、MyOpenWrt ACL、mwan3 及当前构建缓存配置。按之前约定，仅提交修改，**不自动触发新编译**。

## 2026-10-13：固件信息卡片、Docker 存储检测、Bandix Plus

**1. 固件信息（只读）**：`files/www/luci-static/resources/view/status/include/99_photonicat1_info.js` 自动加入 LuCI 状态概览，显示 RK3568 型号、构建时间、内核、编译仓库、ImmortalWrt、QModem 和 Aurora 的 Git 提交标识。RPC 文件在 `/usr/libexec/rpcd/luci.photonicat1`，ACL 只授予 `get_info` 读取权限。**不修改 Aurora 主题文件**。

**2. Docker 外部存储检测（只读）**：上述 LuCI 卡片还展示 `dockerd.globals.data_root`、当前目录所在文件系统可用空间，以及 `/mnt`、`/media` 下真实挂载的块设备。CLI 可执行 `photonicat-docker-storage-check` 检查。**不会自动挂载 SSD、分区、格式化、移动容器镜像、改数据目录或重启 Docker**。如果要改 data-root，请手动确认新盘已挂载，再停服务、复制现有容器数据并变更配置。仅凭路径以 `/mnt` 开头不足以证明该目录真实挂载，代码会核对 `/proc/mounts`。

**3. Bandix Plus 多接口流量统计**：新增 [luci-app-bandix-plus](https://github.com/timsaya/luci-app-bandix-plus) 与 [openwrt-bandix-plus](https://github.com/timsaya/openwrt-bandix-plus)。这是官方推荐给多网口场景的版本，而不是西瓜皮使用的单网口 Bandix。编译时浅克隆上游 `main`、提取前后端软件包，选择 `luci-app-bandix-plus=y`、`bandix-plus=y` 并在 `make defconfig` 后验证。后端由上游提供 ARM64 预编译程序，不是让本工程重新从源码编译 Rust。

**安全默认值**：原上游 Bandix Plus 的 `enable_traffic=1` 在本工程构建时改为 **0（关闭）**，避免首启即挂接 eBPF/流控规则。刷机后需要在 **网络 → Bandix Plus** 中检查接口配置并由你自行启用；要监测多个 LAN/WAN 需确认 eBPF 内核支持，且硬件流量卸载可能造成数据漏计。**不会为 Bandix 自动关闭流量卸载，也不会自动开启限速**。实际是否支持全部接口需要真机测试。

**TD-TECH MT5700M-CN USB 串口补丁**：已按要求采用[西瓜皮原版 `999-add-TD-TECH-option-id.patch`](999-add-TD-TECH-option-id.patch)，编译准备时直接复制到 Rockchip 内核 `patches-6.12`，不修改它的厂商 ID 和接口协议匹配行为。此补丁已纳入**下一次编译**，能否在光影猫设备上正常识别仍需编译及真机验证。其他 FM350、FM160/广和通串口补丁对 Linux 6.12 存在重复规则，暂不合入，分析见 [docs/TDTECH-MT5700M-CN.md](docs/TDTECH-MT5700M-CN.md)。

**构建状态**：上述三项和研究文档已提交 GitHub，但尚未经过新的 GitHub Actions 完整编译和真机验证。普通代码提交不会触发新的构建，只会在下一次手动/定时编译生效。

## 2026-10-13：磁盘、硬件与网络诊断插件（下次编译生效）

- **磁盘管理**：从 ImmortalWrt 25.12 官方 LuCI feed 选择 `luci-app-diskman`，明确启用其 `lsblk` 支持；关闭默认可选的 `btrfs-progs`，避免额外编译庞大的 Btrfs 工具链。不附加分区/格式化/自动挂载脚本；实际操作磁盘前应先备份数据。
- **硬件诊断**：新增 `usbutils`（`lsusb`）、`pciutils`（`lspci`）和 `lsblk`，便于检查光影猫 USB/PCIe 网卡、模组、SSD；`kmod-usb-acm` 增加对 CDC ACM 类型 USB 串口的内核支持，**并不能保证识别所有厂商自定义串口**，也不会修改现有 `option` 驱动/TD-TECH 补丁。
- **网络诊断**：新增 `iperf3`、`tcpdump` 供手工测速/抓包，未设置后台监听、抓包或开机任务。
- **定时重启**：新增官方 `luci-app-autoreboot`，不预设任何定时重启任务。
- **中文界面**：为 DiskMan、Autoreboot、UPnP 同时选择官方简体中文语言包（`luci-i18n-diskman-zh-cn`、`luci-i18n-autoreboot-zh-cn`、`luci-i18n-upnp-zh-cn`）。
- **UPnP**：新增官方 `luci-app-upnp`（其依赖会选择 miniupnpd）。不覆写配置，不预设端口映射；miniupnpd 官方初始配置 `option enabled 0`，需要使用时在 LuCI 中手动配置启用。已有升级保留配置的实际状态以设备为准。
- **编译保障**：原 `scripts/select-packages.py` 在 `feeds install` 完成后选择软件包；`scripts/verify-config.sh` 在 `make defconfig` 后检查全部新增选项以及 DiskMan Btrfs 可选项关闭状态。依赖未满足时构建会直接提示缺项，避免无提示产出缺插件固件。
- **触发规则不变**：仅更新代码及文档；GitHub Actions 的 push 触发路径仍仅为 `.github/photonicat-build-trigger.txt`，未改动该文件，不会因本次提交自动开启新编译。正在运行的任务继续使用启动时检出的提交；保留每周五既定的定时构建。

**兼容状态**：已核对 `immortalwrt/luci` 的 `openwrt-25.12` 分支包含 DiskMan、Autoreboot、UPnP 软件包定义，但这次提交不代表 GitHub Actions 完整编译和光影猫真机验证通过。

## 2026-10-13：修复 Actions #38344162970 的配置校验失败

失败记录：[GitHub Actions #38344162970](https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/actions/runs/38344162970)；于 2026-10-13 12:06（UTC+8）在 **Resolve and verify package selection** 失败，没有进入固件的实际编译阶段。Runner 当时剩余 105 GiB 左右的磁盘空间，不属于 Rust 或空间不足问题。

失败时上传的 `.config` 显示 `luci-app-store` 与 `luci-app-bandix-plus` 选项完全消失，而 `luci-lib-taskd` 和 `taskd` 为未选中。现修复如下：

1. **Bandix Plus 包名**：上游 UI Makefile 通过 `luci.mk` 的 `$(notdir $(CURDIR))` 推断软件包名，旧目录 `package/photonicat-luci-app-bandix-plus` 错误注册为 `photonicat-luci-app-bandix-plus`。现改为 `package/luci-app-bandix-plus`，保留多接口 Bandix Plus 后端和默认关闭流控的配置。
2. **iStore 来源保留**：继续从 LinkEase 官方 `istore;main` feed 取源码。feeds 安装之后使用 `scripts/fix-istore-25.12.sh` 校验四个 iStore 包路径，并在官方 `luci-app-store` Makefile 显式定义 `LUCI_NAME` 和 `PKG_NAME`，避免包身份依赖路径推断。此项针对源码已安装但 Kconfig 选项未出现的问题提供兼容修正，最终成效须由新编译验证。
3. **依赖和检查**：在配置覆盖中显式启用 `luci-lib-taskd`、`luci-lib-xterm`、`taskd`、`script-utils`、`coreutils-stty` 和 `mount-utils`；在 `make defconfig` 后逐项检查。工作流额外报告 `tmp/.packageinfo` 中的实际注册名称，失败时 Artifact 连同配置一起保存元数据，避免再次凭猜测排查。
4. **不改编译启动方式**：不修改专用 push 触发文件 `.github/photonicat-build-trigger.txt`，不手动运行 Actions，不取消或重启现有工作流；原每周五凌晨 02:00 定时构建保持不变。此前新增的 DiskMan、USB/PCIe/网络诊断、定时重启、UPnP 和中文翻译选项也全部保留。

**注意**：这些是基于真实失败日志与 Makefile 的修复提交，尚无新一轮 `make defconfig` 或完整固件编译的成功结果，不能视为已经真机验证。

## LuCI 状态菜单精简

- 移除 **状态 → MultiWAN 管理器** 的概览、状态、网络诊断及故障排查四个子页面；这是无必要的额外状态入口。
- **网络 → MultiWAN 管理器** 的接口、成员、策略及规则配置入口全部保留；`mwan3` 服务、多 WAN 主备策略、QModem 及系统网络设置不做任何改动。
- `scripts/hide-mwan3-status-menu.py` 在官方 LuCI feeds 安装完毕后，精准修改 `luci-app-mwan3` 源码中的菜单 JSON。固件内打包的菜单即不含状态入口，不需要额外开机服务。
- 此项仅影响**后续编译生成的固件**；已刷入的旧固件不会自动改变。

## 2026-10-13：只保留手动编译

- 根据用户要求，已停止 GitHub Actions 的每周定时构建和 push 专用触发文件构建。工作流仅保留 `workflow_dispatch`。
- 后续自行打开 **Actions → Photonicat1 ImmortalWrt QModem Build → Run workflow**，选中 `main` 并确认；`publish=true` 时编译成功自动发布 Release。
- 修改代码或配置本身**不再自动编译**。切换到仅手动编译之前已经开始的运行仍会正常完成。
- 旧版 `.github/photonicat-build-trigger.txt` 保留作为历史记录，但编辑它也不会触发编译。
- Docker Engine、CLI、Compose 和 `luci-app-dockerman` 已在成功的编译 #38353246710 中通过配置校验；Dockerman 官方 LuCI 菜单属于 **服务 → Dockerman JS**，需要设备上存在可执行的 `/etc/init.d/dockerd`、`/usr/bin/dockerd` 和有效的 `/etc/config/dockerd` 才会显示。若菜单未显示，应在设备上检查文件和服务，而不是误认成没有编译。

## 光影猫专用在线固件升级（完整功能 + 严格校验）

上游开源项目：[gooyjq/luci-app-online-upgrade](https://github.com/gooyjq/luci-app-online-upgrade)，GPL-2.0-only，固定源码提交 `6f587f19d7f884ca89e4bfa95bbb9a002a521477`。此项目保留上游许可证，同时提供专属光影猫一代的后端、前端及额外分区保护脚本；不是直接复制无校验的一键升级逻辑。

- **系统 → 在线升级**：默认使用 `PEIT98/ImmortalWrt-Photonicat1-AutoBuild` 的最新正式 Release。支持自定义 GitHub 仓库、`latest` 或指定 Release 标签、可信 HTTPS 下载代理（只用于镜像下载，不用于校验清单）。打开页面自动检查一次；也可手动点击「检查最新固件」。
- **设备/镜像安全检查**：必须满足设备树兼容名称 `ariaboard,photonicat`、当前根文件系统为 ext4 或 squashfs、Release 中存在该设备与当前文件系统一致的确切 `...-sysupgrade[_YYYYMMDDHH].img.gz` 文件及 `SHA256SUMS.txt`。固件大小须在合理范围内；下载后验证文件大小和 SHA256。
- **重要的 Rockchip 磁盘保护**：从实际启动磁盘和已下载镜像提取分区表，要求各分区起始位置与大小完全一致。不同则阻止自动升级，避免重写整张启动盘。通过分区检查后，还必须通过 `/sbin/sysupgrade -T`；任何失败都会终止。
- **一键升级**：经用户确认后启动后台任务，显示检查/下载/校验/备份/刷写进度；固件通过校验后才调用 `sysupgrade`。如选择「保留配置」，执行 `sysupgrade -f 备份文件 镜像`；如选择「不保留配置」，执行 `sysupgrade -n 镜像`。不保留配置会清空当前系统配置的恢复流程，并不会单独格式化外置 Docker 数据盘。
- **强制重装**：即便 GitHub 构建提交与当前版本相同，也可重新刷入。强制重装绝不调用 `sysupgrade -F`，不会绕过设备/校验/分区保护。新旧版本比较依据固件内 `/etc/photonicat1-build-info` 与 Release 的 `build-sources.txt`，缺失时会提示无法准确判断。
- **配置备份**：提供「创建升级前备份」功能；刷写前也会自动生成备份。在 `/boot` **已经挂载为持久分区**时尝试复制备份到 `/boot/photonicat-upgrade-backup.tar.gz`；若未挂载则不会擅自重挂载或修改启动盘，备份只存在临时文件中，可能随升级消失。**请务必先在 LuCI 原生「系统 → 备份/升级」页面下载备份至电脑。**
- **恢复/下载备份**：手动导出和上传恢复使用系统原生的认证 LuCI 备份/升级功能；不恢复上游直接将未经审计的上传压缩包解压到根目录的 `online-upgrade-restore` CGI。
- **禁止自动安装 APK**：不会执行上游 `90-online-upgrade-auto` 的第三方 APK 开机下载，不会自动打开 GitHub Actions 构建；仅用户点击「立即升级/强制重装」并确认时才执行固件更新。

**兼容性状态：目前已经提交源码并执行静态和界面模拟测试，但尚未由下次 GitHub Actions 完整编译或在真实光影猫一代设备上测试下载和刷写。** 首次使用时应先做好救砖准备；遇到分区布局不一致，应走人工确认的升级/恢复路径，不建议关闭保护检查。

## Releases 固件文件名时间戳（手动编译后生效）

- GitHub Actions 固件编译成功后，在收集固件阶段统一取北京时间（Asia/Shanghai）`YYYYMMDDHH`（年、月、日、时；24 小时制），仅重命名 `-sysupgrade.img.gz` 为 `-sysupgrade_YYYYMMDDHH.img.gz`，保留 ext4/squashfs 和设备型号。
- 例如：`immortalwrt-rockchip-armv8-ariaboard_photonicat-ext4-sysupgrade_2026101316.img.gz`、`immortalwrt-rockchip-armv8-ariaboard_photonicat-squashfs-sysupgrade_2026101316.img.gz`。
- 固件字节内容不变，`SHA256SUMS.txt` 在重命名后生成，因此记录的是新名称和对应镜像摘要；清单和构建元数据保持原样。
- `luci-app-online-upgrade` 在线升级器同步支持新旧命名，且必须满足其额外安全检查。已发布的历史 Release 不会重命名，新规则只对下一次用户手动编译后的 Release 生效。
