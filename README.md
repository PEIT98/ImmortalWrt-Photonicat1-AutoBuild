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
| luci-app-clash | 保留 |
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

- 首次 Actions 运行在 `make defconfig` 后缺少 `CONFIG_PACKAGE_qmodem=y`。新的构建过程增强了依赖诊断，但尚不能认为该问题已经修复。
- 原配置选择 `luci-app-clash`，但默认 ImmortalWrt 25.12 与 QModem feeds 未确认提供此包；原始 Clash LuCI 项目较老，若配置校验提示缺失，不应悄悄改成不含代理插件的固件。需要单独选择经验证可用于 25.12 的来源，或确认是否改用 OpenClash。
- QModem 已调整为与西瓜皮相同的 `stable` 分支；ImmortalWrt 仍为 `openwrt-25.12`。stable 版的短信与拨号包依赖不同于 main，因此已同步调整配置校验。

不要把 GitHub Actions 编译成功等同于真机验证通过。
