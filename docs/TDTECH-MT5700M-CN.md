# 5G USB 串口补丁调研及 TD-TECH 集成

更新时间：2026-10-13。

## 已集成：西瓜皮原版 TD-TECH USB 串口补丁

来源：[zzzz0317/immortalwrt-xgp-auto-build/999-add-TD-TECH-option-id.patch](https://github.com/zzzz0317/immortalwrt-xgp-auto-build/blob/main/999-add-TD-TECH-option-id.patch)。

- 本仓库 [999-add-TD-TECH-option-id.patch](../999-add-TD-TECH-option-id.patch) **逐字采用西瓜皮原文件，不缩减或改变匹配条件**。
- 构建时 `scripts/build/prepare.sh` 复制到 `immortalwrt/target/linux/rockchip/patches-6.12/999-add-TD-TECH-option-id.patch`，校验目标文件一致。
- 原补丁修改内核 `drivers/usb/serial/option.c`，增加 `TDTECH_VENDOR_ID 0x3466`，并匹配接口类/子类/协议 `ff/06/{10,12,13,14,1b,1c}`。
- 对此前使用的 MT5700M-CN（`3466:3301`）可尝试自动绑定 USB 串口，免去 `usbserial_generic/new_id` 的临时绑定；仍需确认网络接口继续由 `cdc_ether` 接管。
- 此匹配基于 **厂商 ID + 接口描述符，不限制产品 ID**，与西瓜皮补丁行为相同；实际匹配取决于 USB 接口描述符。
- 本仓库已经选择 `CONFIG_PACKAGE_kmod-usb-serial-option=y`。此补丁只负责内核 USB 串口驱动识别，不会修复 QModem 的串口探测、模组拨号、AT 口抢占或 IPv6 掉线。
- 当前为**已提交编译配置、尚未经下一轮编译及真机验证**。

## 搜索两个西瓜皮自动编译仓库的结果

- [immortalwrt-xgp-auto-build](https://github.com/zzzz0317/immortalwrt-xgp-auto-build)：当前主分支只有上述一个独立的 USB 串口内核 `.patch` 文件。
- [lede-xgp-auto-build](https://github.com/zzzz0317/lede-xgp-auto-build)：当前主分支未找到额外的 USB 串口补丁文件。
- 新版西瓜皮另有 `files/etc/modules.d/90-pcie_mhi` 中的 `pcie_mhi mhi_mbim_enabled=1`，这是 **PCIe MHI/MBIM 驱动参数**，并不是 USB option 串口补丁；不可无条件复制到光影猫。

## 在其他 OpenWrt 仓库找到的串口补丁（尚未合入）

| 补丁来源 | 主要改动 | 当前处理 |
|---|---|---|
| [bkspc/backspacewrt 的 FM350-GL 6.6 补丁](https://github.com/bkspc/backspacewrt/blob/159589c6200271bf2ebf538afb539a97c3bd2304/target/linux/generic/hack-6.6/941-usb-serial-fibocom-fm350-support.patch) | `0e8d:7126`、`0e8d:7127` 的 USB interface 匹配 | **不加入**：Linux 6.12 的 `option.c` 已存在这两个 ID，直接重加可能冲突 |
| [zxlhhyccc/acc-imq-bbr 的 Fibocom 6.1 补丁](https://github.com/zxlhhyccc/acc-imq-bbr/blob/217969a53e743b7e148fd0ad8fa26b92978fc145/master/target/linux/generic/hack-6.1/999-add-fibocom-id-and-zeropacket.patch) | 适配 FM150/FM160 等多个 `2cb7` 产品 ID、`0e8d` FM350，并修改 `usb_wwan.c` ZLP 行为 | **不加入**：部分 `2cb7` ID 在 Linux 6.12 已有，且 `usb_wwan.c` 修改跨设备，需先对照缺失 ID/实际需求 |
| [LEDE 的 TD-TECH 6.18 补丁](https://github.com/coolsnowwolf/lede/blob/ff7be3fa21cae4277a0b2e8d6653b8acce8ac236/target/linux/generic/hack-6.18/932-usb-net-for-td-mt5700.patch) | 与西瓜皮相似的 TD-TECH `option.c` 匹配，针对内核 6.18 的上下文 | **不加入**：当前已采用对应 Linux 6.12 的西瓜皮原补丁 |
| [DotRacel/MT5700M-CN 原厂相关补丁](https://github.com/DotRacel/MT5700M-CN/blob/main/resources/999-tdtech-usb-vendor.patch) | 同类 TD-TECH USB option interface 适配 | **不重复加入** |

## 真机验证（只读）

在连接 MT5700M-CN 的设备上运行：

```sh
echo 'USB 3466:3301:'
lsusb -d 3466:3301
echo 'USB 接口和驱动:'
lsusb -t
echo '串口设备:'
ls -l /dev/ttyUSB* 2>/dev/null
echo 'Option / ECM / QModem 日志:'
dmesg | grep -iE '3466|3301|option|cdc_ether|ttyUSB' | tail -n 50
```

期待结果：对应串口接口绑定 `option` 并创建 `ttyUSB` 端口，同时 USB 网络接口仍绑定 `cdc_ether`。如需要修复 QModem 扫描失败，还须进一步检查 AT 口及对应服务是否抢占串口。

**不要在新的内核版本直接复用 Linux 6.12 补丁**；本仓库会在 `patches-6.12` 缺失时停止准备阶段，防止静默跳过。
