# 光影猫管理（单一软件包）

选择 `luci-app-photonicat-power` 即可同时安装 MCU 后台、光影猫管理页面和 LuCI 顶部设备状态。旧 `pcat-manager-v1`、`luci-mod-battstatus` 和独立电池中文翻译包不再单独编入固件。

MCU 服务使用 [photonicat/rockchip_rk3568_pcat_manager](https://github.com/photonicat/rockchip_rk3568_pcat_manager/tree/v1) 锁定提交 `6f16e4ab4fbba220af932e02e5ef8f1a63f4bafd`，保留原来的 PMU-only 补丁、心跳、看门狗与关机协议。Go 版 `pcat-mgr` 仍禁用，设备默认包已换成此插件。

- **系统 → 光影猫管理**：手动模式、车载/UPS 延时关机、每日定时开关机。
- Aurora 顶栏依次显示 QModem 当前 4G/5G 与模组名称/RSRP 信号、eth0 WAN 和 eth1 LAN 物理链路、每个已加载内核 PHY 的 Wi-Fi 开关状态、电池模式图标和电量；手机窄屏以第二行横向滚动显示。无模组/无服务不显示虚构信号；未加载的无线驱动不占图标位置，双射频网卡显示两个图标。鼠标悬停可查看设备名和状态。
- 显示电量百分比、电池供电/外部供电、电池及充电器电压、板温；15 秒自动刷新。
- **电量显示**：右上角电量开关、低电量提醒开关和阈值（5%～50%，默认 20%）；单独保存，重启保留，不依赖 MCU 在线。
- 低电量提醒只在电池供电且打开路由器后台时弹出，同一浏览器标签页每次低电量过程提醒一次；恢复外部供电或高于阈值 3% 后重新允许提醒，不执行关机。
- 右上角电量可点击进入管理页；页面使用手机适配的电量卡片、供电标识和分区设置。
- MCU 串口 `/dev/ttyS4` 仅由本包内的 `pcat-manager` 打开；LuCI 页面和顶部电量仅通过 `/tmp/pcat-manager.sock` 查询。
- 协议指令：`pmu-status`、`charger-on-auto-start-get/set`、`schedule-power-event-get/set`。
- 车载延时页面输入分钟，协议使用秒；定时模式每天开机/关机各一条，保存需确认替换 MCU 原有计划。
- 车载页面显示只读供电状态及自动倒计时：每 15 秒校准 MCU 剩余时间，期间每秒更新显示；超过 30 秒未更新停止推算。拔电后应显示“电池供电”。手动开机后拔掉实际外部电源可触发延迟关机；MCU 若仍判定外部供电，倒计时将不断重置。
- 延时关机会真实执行系统 `poweroff`，首次建议先备份配置并在外部电源与恢复手段可用的情况下测试。
- 不访问任何串口，不触碰 QModem/mwan3，不包含二代直连电源模式。
- MCU 没有提供有效电压数据时，禁止保存电源策略。
- 顶部仍使用 `battstatus.js`、`luci.battstatus` RPC 和其它机型的检测分支；新增只读 `luci.photonicat_header` 查询 QModem、物理网口、无线 PHY 和 PMU 模式。`getBatteryStatus` 使用只读 `battery` RPC；简体中文 `.lmo` 随本包安装。所有翻译 `.po` 源码保留在 `po/`，当前固件只启用原先选中的简体中文。
- 保留 `/etc/config/luci_battstatus`、`/etc/pcat-manager.conf` 和 `/etc/pcat-manager-userdata.conf` 的升级配置，升级后原有电池显示设置与 MCU 设置继续生效。

### MCU Socket 兼容说明

官方 C 版电源服务采用 NUL 分隔的异步 JSON 协议。通过 shell 管道发送时，必须使用 `socat STDIO,ignoreeof`，避免 stdin EOF 立即向 Socket 发送半关闭而令服务端丢弃待发送的响应。此方式不会打开 `/dev/ttyS4`，保持原 MCU 看门狗和 QModem 不变。

### 页面加载优化

- 页面先显示，再异步加载电量和模式；手机端说明文字已精简。
- 首次查询仍将 `pmu-status`、`charger-on-auto-start-get`、`schedule-power-event-get` 合并为一个只读请求。
- 只读请求使用 `socat -T 0.25` 减少 MCU Socket 关闭等待；响应不完整或校验失败则用原有 `-T 1` 自动重试。
- 每 15 秒通过只读 `runtime` 查询电池及 UPS 剩余时间，不重复读取定时计划，也不覆盖正在编辑的设置；每秒倒计时只更新浏览器文字。
- 顶部电量保持每 5 秒一次只读电池查询；顶部设备状态每 15 秒刷新一次。关闭顶部显示和低电量提醒后，电量查询停止，设备状态仍会读取电源模式。
- 显示设置由 `luci.battstatus getSettings/setSettings` 存入 `/etc/config/luci_battstatus`，只提交这一份配置；保存模式的 MCU 写入及其应答校验仍保持 `-T 1`。
- 不变更 MCU 串口协议或 QModem 配置。构建时仍使用原先锁定的上游 C 源码与本地 PMU-only/UPS 补丁，只将产物安装到这个软件包。
