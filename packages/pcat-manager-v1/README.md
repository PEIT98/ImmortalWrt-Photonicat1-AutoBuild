# 光影猫一代 PMU-only 电池管理器

上游：[photonicat/rockchip_rk3568_pcat_manager](https://github.com/photonicat/rockchip_rk3568_pcat_manager/tree/v1)，锁定提交 `6f16e4ab4fbba220af932e02e5ef8f1a63f4bafd`。

- 原厂 v1 守护进程独占 `/dev/ttyS4`，替代 ImmortalWrt Go 版 `pcat-mgr`，提供 `/tmp/pcat-manager.sock`。
- 保留 MCU 心跳/看门狗、关机、电池、定时和充电模式协议。
- 将上游 modem-manager 改为无操作实现，避免与 QModem 在 USB、Modem GPIO、RF-kill 等方面冲突。
- 使用上游 `--distro` 模式，禁用旧式网络状态和 mwan3 检查线程。
- 上游 C 程序在收到普通 SIGTERM 时会触发整机重启；已对此改为关闭 MCU watchdog 后平稳退出。真实关机操作仍遵循原流程。
- 旧顶部 `luci-mod-battstatus` 不再编入固件，但仓库保留所有源码。新电源管理 LuCI 页面直接读取 PMU 状态并显示电池信息。
- **风险：目前还没有完成真实设备编译与刷机测试。** 首次刷机务必备份并准备 Rockchip 刷机恢复手段；不要手动同时运行两个串口管理器。
