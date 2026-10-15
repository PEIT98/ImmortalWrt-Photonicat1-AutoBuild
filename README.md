# 光影猫一代 ImmortalWrt 自动编译

基于 **ImmortalWrt 25.12**，适用于 **Ariaboard Photonicat 一代（RK3568）**。

- 固件源码：[ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `openwrt-25.12`
- 设备参考：[光影猫一代](https://github.com/a757814283/ImmortalWrt_Photonicat1)
- 5G 模组管理：[LianXia233/QModem](https://github.com/LianXia233/QModem) `main`（内置短信转发、Rust AT 后端）

## 主要功能

| 分类 | 内置功能 |
| --- | --- |
| 5G / 网络 | QModem Next（含短信）、mwan3、OpenClash |
| 系统界面 | Aurora 主题、电池状态、光影猫一代电源管理（实验性）、CPU 调频、ttyd 网页终端、固件信息卡片 |
| 应用与容器 | iStore、Docker、Docker Compose、Dockerman |
| 管理工具 | DiskMan、Bandix Plus、定时重启、UPnP |
| 诊断工具 | `lsusb`、`lspci`、`lsblk`、`iperf3`、`tcpdump` |
| 驱动支持 | USB QMI / MBIM / 串口、PCIe / SDIO 无线网卡 |

无线驱动包括 Realtek RTL8922AE / RTL8852BE / RTL8852CE、MediaTek MT7921 / MT7925 / MT7916、Qualcomm ath10k / ath11k / ath12k。板载 QCA9377 系列使用 SDIO 驱动，是否可用取决于板子实际硬件和固件支持。内置 [TD-TECH 3466 USB 串口补丁](999-add-TD-TECH-option-id.patch)。

**默认设置：** Bandix Plus 流量功能不开启；Docker 存储检测仅显示信息，不执行挂载、迁移或格式化。固件仅生成 **squashfs sysupgrade** 镜像，不生成 ext4 镜像；`kmod-fs-ext4` 仍保留，支持 ext4 硬盘或 U 盘。

## CPU 调频插件

已将完整 [luci-app-cpufreq](packages/luci-app-cpufreq/) 放入项目，包含网页设置、LuCI 菜单、RPC 权限与中文翻译。构建时优先使用本地源码，避免 Feeds 同名插件冲突；实际 CPU 调频服务依然使用官方 `cpufreq` 包。以后可直接编辑项目中的插件源码，不必新增修复脚本。

## 电池指示插件

完整的 [luci-mod-battstatus](packages/luci-mod-battstatus/) 已放进项目：包含电池 RPC、ACL 权限、上游全部语言和修改版 [battstatus.js](packages/luci-mod-battstatus/htdocs/luci-static/resources/preload/battstatus.js)。直接作为本地 LuCI 包参与编译，不再使用 `files/` 单独覆盖 JS 或运行 Python 修复脚本；保留 5 秒轮询及 Aurora 紧凑显示。

## 光影猫一代电源管理（实验性）

内置 [luci-app-photonicat-power](packages/luci-app-photonicat-power/)：系统 → 光影猫电源管理，支持手动、车载/UPS 延时关机、每日定时开关机。按官方 [pcat-manager v1 协议](https://github.com/photonicat/rockchip_rk3568_pcat_manager/tree/v1) 实现，仅使用控制 Socket，不操作 MCU 串口。**现用 Go 版 pcat-mgr 与官方 C 版接口并不保证兼容**：没有 `/tmp/pcat-manager.sock` 时会显示不可用，不替换现有守护进程、不影响电池指示或 QModem。具体限制见插件 README。

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

## 多 WAN 优先级

**主备优先级（从高到低）：第一，有线 WAN（`wan`）；第二，Wi-Fi 中继（`wwan`）；第三，QModem 5G/LTE（动态接口）。**

mwan3 使用数值越小优先级越高的 `metric`。QModem 的 IPv4 拨号接口由同步脚本自动识别，可能是 `6_1`、`6_2` 或自定义别名；更换模组、接口变化及重启后会尝试自动同步。无需手动设置固定接口名。

Wi-Fi 中继使用 `wwan` 接口；QModem 拨号接口由系统自动识别，无需手动指定接口名称。mwan3 自动按照有线 WAN、Wi-Fi、5G 的顺序进行故障切换。查看当前动态绑定和在线状态：

```sh
uci -q get mwan3.qmodem_priority3.interface
mwan3 status
```

## 编译与下载

1. 打开 [GitHub Actions](https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/actions/workflows/build.yml)。
2. 选择 **Run workflow**，分支选 `main`，点击运行。
3. 编译完成后，从 [Releases](https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/releases) 下载固件；`publish=true` 时自动发布。

**仅手动编译**，普通代码提交不会启动 Actions。构建使用源码下载缓存和 CCache；Release 附带 SHA256 校验、软件包清单和源码版本信息。sysupgrade 镜像文件名包含北京时间 `YYYYMMDDHH`。

刷机前请备份设备配置并准备恢复方案。编译成功不等于已经通过真机测试。

## 新增插件记录

仅在**新增插件**时更新此处；日常修复、配置调整和已不使用的功能不写历史记录。

- **2026-10-12**：Aurora 主题、ttyd 网页终端。
- **2026-10-13**：iStore、Docker / Docker Compose / Dockerman、Bandix Plus、DiskMan、定时重启、UPnP。
- **2026-10-15**：光影猫一代电源管理（实验性，仅连接兼容 MCU Socket）。

其余插件和驱动以 [独立选包配置](photonicat1.config) 为准。
