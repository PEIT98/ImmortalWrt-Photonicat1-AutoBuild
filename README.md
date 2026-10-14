# 光影猫一代 ImmortalWrt 自动编译

基于 **ImmortalWrt 25.12**，适用于 **Ariaboard Photonicat 一代（RK3568）**。

- 固件源码：[ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `openwrt-25.12`
- 设备参考：[光影猫一代](https://github.com/a757814283/ImmortalWrt_Photonicat1)
- 5G 模组管理：[QModem](https://github.com/FUjr/QModem) `stable`

## 主要功能

| 分类 | 内置功能 |
| --- | --- |
| 5G / 网络 | QModem Next（含短信）、mwan3、OpenClash |
| 系统界面 | Aurora 主题、电池状态、CPU 调频、ttyd 网页终端、固件信息卡片 |
| 应用与容器 | iStore、Docker、Docker Compose、Dockerman |
| 管理工具 | DiskMan、Bandix Plus、定时重启、UPnP |
| 诊断工具 | `lsusb`、`lspci`、`lsblk`、`iperf3`、`tcpdump` |
| 驱动支持 | USB QMI / MBIM / 串口、PCIe / SDIO 无线网卡 |

无线驱动包括 Realtek RTL8922AE / RTL8852BE / RTL8852CE、MediaTek MT7921 / MT7925 / MT7916、Qualcomm ath10k / ath11k / ath12k。板载 QCA9377 系列使用 SDIO 驱动，是否可用取决于板子实际硬件和固件支持。内置 [TD-TECH 3466 USB 串口补丁](999-add-TD-TECH-option-id.patch)。

**默认设置：** Bandix Plus 流量功能不开启；Docker 存储检测仅显示信息，不执行挂载、迁移或格式化。

## 配置管理与编译优化

- [`photonicat1.config`](photonicat1.config)：集中维护所有强制启用及明确禁用的插件、驱动和编译开关（不是完整的 OpenWrt `.config`）。
- [`scripts/prepare.sh`](scripts/prepare.sh)：继承原光影猫参考配置，准备 Feeds、补丁和系统文件；不覆盖现有网络设计。
- [`scripts/select-packages.py`](scripts/select-packages.py)：在 Feeds 安装后应用上述配置，继承未明确修改的选项。
- [`scripts/verify-config.sh`](scripts/verify-config.sh)：在 `make defconfig` 后校验必需插件和依赖；缺失则停止编译，防止静默丢包。
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

其余插件和驱动以 [独立选包配置](photonicat1.config) 为准。
