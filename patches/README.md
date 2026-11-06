# 补丁分类

这里保存补丁原文件、插入片段及集中管理的 [QM 修复](qmodem/README.md)。其余补丁执行脚本位于 [scripts/patches/](../scripts/README.md#补丁脚本)，由构建流程调用。

| 分类 | 文件 | 用途与接入位置 |
| --- | --- | --- |
| 内核 / USB 串口 | [999-add-TD-TECH-option-id.patch](kernel/999-add-TD-TECH-option-id.patch) | 为 `3466` 的指定接口增加 `option` 驱动匹配；由 `scripts/build/prepare.sh` 复制到 Rockchip `patches-6.12/` |
| 无线 / ath11k | [999-photonicat-nfa765-e108-firmware.patch](wireless/999-photonicat-nfa765-e108-firmware.patch) | 仅为 NFA765 hw2.1 `105b:e108` 选择专用固件；由 `scripts/build/bundle-nfa765-e108.sh` 安装到 mac80211 的 `patches/ath11k/` |
| 存储 / Rockchip | [swrt-upgrade-partitions.sh](storage/swrt-upgrade-partitions.sh) | 分区比较函数片段，由 `scripts/patches/storage/enable-emmc-autogrow.sh` 插入升级脚本，保留已扩大的根分区 |
| QModem / 计时与开机扫描 | [qmodem/](qmodem/README.md) | 计时、网卡等待及条件补扫集中保存，构建统一调用 `patches/qmodem/apply.sh` |

`storage/` 中的 `.sh` 是供插入的函数片段，不单独运行。QM 开机等待网卡稳定后调用官方全扫描入口；拨号使用上游逻辑。

来源：TD-TECH 保留西瓜皮原版；NFA765 说明见 [固件目录](../firmware/nfa765-e108/README.md)；存储片段基于 SlAlot/ImmortalWrt_Photonicat1 `ae655185`，许可证为 AGPL-3.0-only。
