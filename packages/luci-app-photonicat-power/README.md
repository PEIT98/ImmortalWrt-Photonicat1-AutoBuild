# 光影猫一代 LuCI 电源管理（安全移植版）

- 菜单：系统 → 光影猫电源管理。
- 三种模式：手动、车载/UPS（断电延时）、定时（每日开机/关机各一条）。
- 官方一代协议：`photonicat/rockchip_rk3568_pcat_manager` 的 `v1` 分支，`/tmp/pcat-manager.sock`，JSON + NUL 结尾。
- 车载 `timeout` 在原版 C MCU 服务中是**秒**（官方网页说明曾显示分钟），页面输入分钟后乘以 60。
- 切换模式会清除另一模式的 MCU 计划，**不会**碰网络/QModem/防火墙/现有电池显示。
- 仅允许 `ariaboard,photonicat`，不支持二代专有的直连电源模式。
- **重要兼容性限制**：当前 ImmortalWrt 25.12 光影猫一代默认安装 Go 版 `pcat-mgr`（FUSE 电池读取），**不保证**提供旧 C 版 Socket。本插件不安装、不替换 MCU 守护进程；Socket 不存在时界面显示不可用，不会直接打开 `/dev/ttyS4`，避免串口争用和看门狗异常。
- 本阶段是低风险 UI 与官方 Socket 接口移植；只有现场具备兼容 Socket 才能实际下发 MCU 指令。需要让原厂模式在 Go 版 pcat-mgr 上可用，仍须先核实其实际控制 API 或安全扩展对应守护进程。
- 定时页为了简单只提供每天两条计划；原版协议支持更复杂的星期设置。本页保存会覆盖原有计划，点击前需二次确认。
- 依赖：LuCI、rpcd、socat、libubox/jshn（系统自带）。
- 验证：`ubus call luci.photonicat_power status '{}'`；`ls -l /tmp/pcat-manager.sock`。
