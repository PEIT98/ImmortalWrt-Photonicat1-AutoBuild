# 光影猫一代 LuCI 电源、电池管理

- **系统 → 光影猫电源管理**：手动模式、车载/UPS 延时关机、每日定时开关机。
- 显示电量百分比、电池供电/外部供电、电池及充电器电压、板温；15 秒自动刷新。
- MCU 串口 `/dev/ttyS4` 仅由 `pcat-manager-v1` 打开；本插件仅通过 `/tmp/pcat-manager.sock` 发送官方 JSON+NUL 控制消息。
- 协议指令：`pmu-status`、`charger-on-auto-start-get/set`、`schedule-power-event-get/set`。
- 车载延时页面输入分钟，协议使用秒；定时模式每天开机/关机各一条，保存需确认替换 MCU 原有计划。
- 车载页面新增只读供电状态及剩余秒数（点击“刷新状态”更新）；拔电后应显示“电池供电”。手动开机后拔掉实际外部电源可触发延迟关机，但需要更新后的 pcat-manager-v1 包；MCU 若仍判定外部供电，倒计时将不断重置。
- 延时关机会真实执行系统 `poweroff`，首次建议先备份配置并在外部电源与恢复手段可用的情况下测试。
- 不访问任何串口，不触碰 QModem/mwan3，不包含二代直连电源模式。
- MCU 没有提供有效电压数据时，禁止保存电源策略。
- 顶部 `luci-mod-battstatus` 已恢复打包，使用本插件只读 `battery` RPC；保留 Aurora 电池显示，不恢复旧 Go MCU/FUSE 管理器。需要真机验证。

### MCU Socket 兼容说明

官方 C 版电源服务采用 NUL 分隔的异步 JSON 协议。通过 shell 管道发送时，必须使用 `socat STDIO,ignoreeof`，避免 stdin EOF 立即向 Socket 发送半关闭而令服务端丢弃待发送的响应。此方式不会打开 `/dev/ttyS4`，保持原 MCU 看门狗和 QModem 不变。

### 页面加载优化

- 页面先显示，再异步加载电量和模式；手机端说明文字已精简。
- 首次查询仍将 `pmu-status`、`charger-on-auto-start-get`、`schedule-power-event-get` 合并为一个只读请求。
- 只读请求使用 `socat -T 0.25` 减少 MCU Socket 关闭等待；响应不完整或校验失败则用原有 `-T 1` 自动重试。
- 每 15 秒仅查询电池状态；保存模式的 MCU 写入及其应答校验仍保持 `-T 1`。
- 不变更 pcat-manager-v1、MCU 串口或 QModem 配置。
