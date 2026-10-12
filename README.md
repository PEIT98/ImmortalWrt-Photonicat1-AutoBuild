# 光影猫一代 ImmortalWrt + QModem 自动编译

适用 **Ariaboard Photonicat 一代（RK3568）**，**不是光影猫二代**。当前为首次编译测试工程，尚未完成 GitHub Actions 编译及真机测试。

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
| luci-app-openclash | 保留 |
| luci-app-cpufreq | 保留 |
| luci-mod-battstatus | 保留 |
| ath11k PCI / WCN6855 固件、USB QMI / MBIM 等驱动 | 保留 |
| 旧 ModemBand、sms-tool-js | 移除 |
| PassWall、SmartDNS、ZeroTier | 移除 |

## WAN 优先级

**有线 WAN（wan） > Wi-Fi 中继（wwan） > QModem 5G/LTE（wwan_5g）**

预置 `files/etc/config/mwan3` 作为 IPv4 故障切换策略。**初次启动必须手动完成：**

1. 在 LuCI 无线设置中为 Wi-Fi STA 填写自己的 SSID/密码，绑定网络 `wwan`。
2. 在 QModem 中扫描并设置模组，将 **Alias/别名** 设为 `wwan_5g`，配置 APN 并拨号。
3. 检查 WAN 防火墙区域、`mwan3` 在线状态和真正的主备切换。不要同时让原有 DHCP `usb0` 接口和 QModem 接管同一模组。

**注意**：QModem Next 和传统 `luci-app-qmodem` UI 不应同时选用；其单独的 `luci-app-qmodem-mwan` 依赖传统 UI，所以本工程采用通用 `luci-app-mwan3`。

## 手动编译

到 [Actions](../../actions/workflows/build.yml) → **Photonicat1 ImmortalWrt QModem Build** → **Run workflow**，选择 `publish=true`（默认）并运行。

## 自动编译

GitHub Actions 设定 **每周五中国/新加坡时间凌晨 02:00**（UTC 周四 18:00）自动触发。GitHub 的计划任务可能延迟；需保持仓库 Actions 和定时任务启用。

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
