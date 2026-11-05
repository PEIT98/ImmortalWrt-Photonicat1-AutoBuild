# 光影猫一代 Pwrt 自动编译

基于 [ImmortalWrt 25.12](https://github.com/immortalwrt/immortalwrt/tree/openwrt-25.12)，适用于 **Ariaboard Photonicat 一代（RK3568）**。

## 主要功能

| 分类 | 内置功能 |
| --- | --- |
| 5G / 网络 | 官方 QModem Next + Generic、mwan3（默认关闭）、OpenClash（内置 Meta 内核）、Travelmate、SQM/CAKE |
| 系统界面 | Aurora 主题及设置、顶部设备状态、光影猫电池与电源管理（电源控制实验性）、CPU 调频、ttyd |
| 应用与管理 | iStore、Docker / Compose / Dockerman、文件管理、在线升级、定时重启、UPnP |
| 存储与工具 | eMMC 自动扩容、DiskMan、USB 硬盘保活（默认关闭）、Bandix Plus（流量统计默认关闭）、常用诊断工具 |
| 驱动支持 | USB 模组数据与 AT 串口、板载 SDIO 及多种 PCIe 无线网卡、TD-TECH 串口补丁、NFA765 E108 专用固件 |

QModem 使用官方扫描与拨号逻辑，菜单为“移动网络”；Generic 共用其后台。mwan3 按需手动配置并启用。

## 默认网络设置

| 项目 | 默认值 |
| --- | --- |
| 后台地址 | [172.16.0.1](http://172.16.0.1/) |
| 后台 / SSH 账号及密码 | `root` / `photonicat` |
| 主机名 / 界面品牌 | `Pwrt` |
| 板载 SDIO Wi-Fi | `Pwrt`（优先 2.4GHz） |
| M.2 单射频 Wi-Fi | 优先 5GHz `Pwrt-5G`；无可用 5GHz 信道时回退 `Pwrt-2.4G` |
| M.2 双射频 Wi-Fi | 支持同时双频时分别为 `Pwrt-2.4G`、`Pwrt-5G` |
| Wi-Fi 密码 / 加密 | `photonicat` / WPA2-PSK |
| 5GHz 设置 | 优先 AX / 80MHz；信道跟随驱动检测，通常为 36 |

以上为首次刷入或恢复出厂的默认值；保留配置升级时沿用已有网络、无线及密码设置。
频段回退依据驱动能力，热点实际启动仍需真机验证；旧默认主机名会迁移为 `Pwrt`，自定义主机名保留。

## 编译与下载

1. 打开 [GitHub Actions](https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/actions/workflows/build.yml)，选择 **Run workflow**，分支选 `main`。
2. 保持 `publish=true`，编译成功后自动上传为**预发布版**。
3. 从 [Releases](https://github.com/PEIT98/ImmortalWrt-Photonicat1-AutoBuild/releases) 下载 SquashFS sysupgrade 镜像；测试正常后可手动转为正式版。

**仅手动编译，普通提交不会启动编译。** 在线升级入口为“系统 → 在线升级”，默认国内加速，校验完成后手动确认刷写。刷机前请备份配置。

固件文件名：`Pwrt-P1_YYYYMMDDHH.img.gz`（北京时间，SquashFS sysupgrade）。旧更新器不识别短文件名时，先手动上传升级一次。

## 详细说明

- 配置与构建：[插件和驱动配置](photonicat1.config) · [构建脚本说明](scripts/README.md)
- 系统管理：[光影猫管理与软件源](packages/luci-app-photonicat-power/README.md) · [CPU 调频](packages/luci-app-cpufreq/README.md) · [在线升级](packages/luci-app-online-upgrade/README.md)
- 存储与固件：[eMMC 扩容](docs/STORAGE-RECOVERY.md) · [USB 硬盘保活](packages/luci-app-swrt-disk-keepalive/README.md) · [NFA765 E108 固件](firmware/nfa765-e108/README.md)

参考与来源：[光影猫设备配置](https://github.com/a757814283/ImmortalWrt_Photonicat1) · [官方 QModem](https://github.com/FUjr/QModem) · [PEIT98 Generic](https://github.com/PEIT98/luci-app-qmodem-generic)（复刻自 [LianXia233](https://github.com/LianXia233/luci-app-qmodem-generic)）。

<details>
<summary>新增插件记录</summary>

仅在**新增插件**时更新此处；日常修复、配置调整和已不使用的功能不写历史记录。

- **2026-10-12**：Aurora 主题、ttyd 网页终端。
- **2026-10-13**：iStore、Docker / Docker Compose / Dockerman、Bandix Plus、DiskMan、定时重启、UPnP。
- **2026-10-15**：光影猫一代电源管理（实验性，仅连接兼容 MCU Socket）。
- **2026-10-17**：QModem Generic（引用 PEIT98 自有复刻仓库 `main`，与官方 QModem Next 共存）。
- **2026-10-17**：在线升级（完整本地插件，适配本仓库光影猫固件）。
- **2026-10-17**：文件管理、Aurora 设置、Travelmate 无线中继、SQM/CAKE。

- **2026-11-03**：USB 硬盘保活（默认关闭，支持稳定标识和可选 USB 防挂起）。

</details>
