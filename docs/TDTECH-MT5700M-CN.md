# TD-TECH MT5700M-CN USB 串口驱动适配研究（尚未启用补丁）

参考：[西瓜皮 ImmortalWrt 25.12 的 999-add-TD-TECH-option-id.patch](https://github.com/zzzz0317/immortalwrt-xgp-auto-build/blob/main/999-add-TD-TECH-option-id.patch)。

## 已确认的信息

- 用户此前在 MT5700M-CN 上看到 USB ID **3466:3301**。
- USB If0/If1 走 `cdc_ether`，If2～If5 曾需要用 `usbserial_generic` 和 `new_id` 手动绑定，产生 `/dev/ttyUSB0`～`ttyUSB3`。
- 西瓜皮补丁修改内核 `drivers/usb/serial/option.c`，添加 `TDTECH_VENDOR_ID 0x3466` 和六条 `USB_VENDOR_AND_INTERFACE_INFO(0x3466, 0xff, 0x06, 0x10/12/13/14/1b/1c)`。
- 该宏匹配的是**厂商 ID + USB 接口类/子类/协议**；并非只针对 `3466:3301`，会影响同厂商其他满足接口描述符的设备。
- 其目的只是让 option 驱动自动声明匹配的 USB serial 接口；**不修复** QModem 的 AT 端口扫描、APN、拨号或 IPv6 状态逻辑。

## 更谨慎的补丁方向（待 USB 描述符确认后才应用）

将宏改成限制产品 ID 的 `USB_DEVICE_AND_INTERFACE_INFO(0x3466, 0x3301, 0xff, 0x06, protocol)`，
并且**只选中串口接口实际出现的 protocol**，不能直接拷贝所有六项，也不能匹配 If0/If1 的网络接口。
产品 ID 只来自此前确认为 MT5700M-CN 的设备记录，仍需读取其目前真实 USB 描述符才可确定接口编号与 protocol 对应关系。

在带 MT5700M-CN 的设备上，先运行下列**只读诊断**：

```sh
lsusb -d 3466:3301
lsusb -t
lsusb -v -d 3466:3301 2>/dev/null | grep -E 'bInterfaceNumber|bInterfaceClass|bInterfaceSubClass|bInterfaceProtocol' || true
for x in /sys/bus/usb/devices/*:*; do
    [ -f "$x/bInterfaceClass" ] || continue
    base="${x%:*}"
    [ -f "$base/idVendor" ] && [ -f "$base/idProduct" ] || continue
    [ "$(cat "$base/idVendor")" = 3466 ] && [ "$(cat "$base/idProduct")" = 3301 ] || continue
    printf '%s if=%s class=%s sub=%s proto=%s driver=%s\n' "$x" \
      "$(cat "$x/bInterfaceNumber")" "$(cat "$x/bInterfaceClass")" \
      "$(cat "$x/bInterfaceSubClass")" "$(cat "$x/bInterfaceProtocol")" \
      "$(basename "$(readlink -f "$x/driver" 2>/dev/null)" 2>/dev/null)"
done
```

## 构建建议与边界

1. 确认 If2～If5 对应的 class/subclass/protocol，不对未知接口添加内核匹配。
2. 如确认需适配，在 `target/linux/rockchip/patches-6.12` 放置定向内核 patch，并用 `patch --dry-run` / 首次编译验证。
3. 在固件内保留已有 `kmod-usb-serial-option`，不要强制解绑 `cdc_ether` 或抢占 QModem AT 口。
4. 真机检查 `dmesg`、`lsusb -t`、`/dev/ttyUSB*`、AT 通信和 ECM 拨号；发生异常立即撤回补丁。
5. **目前此项仅研究文档，不在默认编译中修改内核代码。**
