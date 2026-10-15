# 电池状态插件 luci-mod-battstatus

恢复光影猫一代 LuCI 顶部电池图标，保留全部上游翻译、原版电池 RPC 协议及 Aurora 紧凑显示样式。

- **数据来源**：光影猫一代 `luci.battstatus getBatteryStatus` 通过只读 `ubus call luci.photonicat_power battery` 读取 `pcat-manager-v1` 的电池百分比和供电状态，不访问 `/dev/ttyS4`，也不使用旧 Go 版的 FUSE 电池文件。
- 其他设备：保留原有电池检测分支，不修改光影猫二代与其它型号支持。
- 前端：沿用 `battstatus.js` 的 5 秒轮询、Aurora 百分比/紧凑图标、低电量提示以及其它主题的原生显示。
- 系统 → 光影猫电源管理中可保存右上角显示开关、低电量提醒开关及阈值；使用独立 `/etc/config/luci_battstatus`，不写 MCU 和网络配置。两项都关闭时不再从顶部轮询 MCU。
- 点击顶部电量可进入电池管理；低电量时仅在电池供电下提醒，使用浏览器标签页会话去重，外部供电或电量回升后重新允许提醒。
- `LUCI_DEPENDS` 确保电源管理插件存在；其只读 `battery` RPC 现已加入 LuCI ACL。
- `photonicat1.config` 启用此插件及简体中文翻译；`scripts/build/verify-config.sh` 会检查编译选择。

原项目上游为 ImmortalWrt LuCI `openwrt-25.12`，Apache-2.0 许可。**此版本尚需真机编译/显示验证。**
