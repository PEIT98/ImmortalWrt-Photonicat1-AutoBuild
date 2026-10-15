# 光影猫一代 LuCI 电源、电池管理

- **系统 → 光影猫电源管理**：手动模式、车载/UPS 延时关机、每日定时开关机。
- 显示电量百分比、电池供电/外部供电、电池及充电器电压、板温；15 秒自动刷新。
- MCU 串口 `/dev/ttyS4` 仅由 `pcat-manager-v1` 打开；本插件仅通过 `/tmp/pcat-manager.sock` 发送官方 JSON+NUL 控制消息。
- 协议指令：`pmu-status`、`charger-on-auto-start-get/set`、`schedule-power-event-get/set`。
- 车载延时页面输入分钟，协议使用秒；定时模式每天开机/关机各一条，保存需确认替换 MCU 原有计划。
- 不访问任何串口，不触碰 QModem/mwan3，不包含二代直连电源模式。
- MCU 没有提供有效电压数据时，禁止保存电源策略。
- 顶部 `luci-mod-battstatus` 暂停打包，原源码保留。**新的管理器仍需编译、刷机和真机验证**。
