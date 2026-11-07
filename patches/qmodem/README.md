# QModem USB 适配

模组插槽仅使用 USB；M.2 E-key 的 PCIe 用于 Wi-Fi。QModem 基于官方 `stable`，扫描和 AT 工具设置参考西瓜皮项目的 [首启脚本](https://github.com/zzzz0317/immortalwrt-xgp-auto-build/blob/127c70512101b870ea481850cb6357311a65f8ac/files/etc/uci-defaults/zzzz-custom)。保留 Next、Generic 界面；仅 FM350 自动 APN 模式在拨号前读取当前 PDP 的 APN。

## 文件与调用

| 文件 | 作用 |
| --- | --- |
| [apply.sh](apply.sh) | 构建和源码校验共用入口，应用计时修复、USB 适配及 FM350 自动 APN |
| [fix-qmodem-monotonic-clock.sh](fix-qmodem-monotonic-clock.sh) | 保留单调时钟修复，避免系统校时回拨卡住扫描队列和超时等待 |
| [fix-qmodem-usb.sh](fix-qmodem-usb.sh) | 原生开机延时扫描限定为 USB，网卡热插拔跳过 PCIe，安装下方默认值 |
| [fix-fm350-auto-apn.sh](fix-fm350-auto-apn.sh) | 构建时在上游 AT 拨号入口接入 FM350 专用 APN 片段 |
| [fm350-auto-apn.sh](fm350-auto-apn.sh) | 安装至 QModem 的 fixes 目录，只在 FM350 自动 APN 模式读取当前 PDP；不写入 UCI |
| [usb-defaults.sh](usb-defaults.sh) | 安装为 `/etc/uci-defaults/99-qmodem-usb`，首启设置原生扫描和 AT 工具 |

从仓库根目录执行：

```sh
sh patches/qmodem/apply.sh immortalwrt/feeds/qmodem
```

旧网卡稳定等待和条件补扫片段及对应测试已移除。补丁执行脚本仅在构建主机运行，公共文本处理函数使用 [scripts/lib/patch.sh](../../scripts/lib/patch.sh)。

## 原生扫描与 AT 工具

| 设置 | 默认值与行为 |
| --- | --- |
| `start_delay` | `15`，采用上游开机延时扫描；服务本身仍立即启动 |
| `enable_usb_scan` | `1`，保留上游 USB 扫描调度 |
| `enable_pcie_scan` / `try_preset_pcie` | 均为 `0`，不扫描或预探测 PCIe 模组槽位 |
| `at_tool` | `1`，使用 `sms_tool_q`；USB `3466:3301`（TD-TECH / MT5700）沿用西瓜皮例外，删除此项并退回 `tom_modem` |

上游 `boot()` 的延时入口和启用 USB 扫描后的入口均保留，均只发送 USB 扫描请求；队列去重和单模组重试仍由官方扫描器处理。不增加网卡稳定检测、条件补扫、独立服务、固定槽位或串口排序。网卡热插拔只接受 USB；USB 原有的热插拔延时和处理逻辑保留。

首启默认值只提交 `qmodem` 的上述字段，不修改持久 APN、PDP、模组 AT 端口、数据网卡或拨号开关。TD-TECH 的例外仅切换 AT 工具，不关闭拨号。不引入西瓜皮的固定槽位、PCIe T99W373 禁拨规则或 QM-mwan 联动；mwan3 继续默认关闭。

## FM350 自动 APN

只在 QModem 识别为 FM350 / FM350-GL，且 APN 为空或 auto、PDP 索引有效时生效。依次查当前 PDP 的 CGDCONT、CGCONTRDP，再按已知国内运营商 IMSI 选择 cmnet、3gnet、ctnet；过滤 IMS、SOS 等非数据 APN。手动 APN 原样保留，其他模组不额外发送 AT 命令。未取得可用 APN 时交由上游拨号处理。

## 驱动范围

驱动选择集中在 [photonicat1.config](../../photonicat1.config)，由 [verify-config.sh](../../scripts/checks/verify-config.sh) 在 `make defconfig` 后核对。

| 类型 | 处理 |
| --- | --- |
| USB QMI | 保留厂家 `kmod-qmi_wwan_q/f/s` 与 Tom 定制 `quectel-CM-5G-M`；关闭重复的通用 QMI 和 `uqmi` |
| USB MBIM / ECM / NCM / RNDIS | 保留对应 USB 网卡驱动和 `umbim`，按模组实际 USB 模式绑定 |
| USB AT 串口 | 保留 `option`、`qcserial` 等和 [TD-TECH 内核补丁](../kernel/999-add-TD-TECH-option-id.patch)，端口选择沿用官方规则 |
| 模组 PCIe | 关闭 QM 的 PCIe、厂家 MHI、T7xx 选项及 `kmod-pcie_mhi`、`kmod-mtk-t7xx` |
| PCIe Wi-Fi | 保留 ath11k、ath12k、rtw89 等现有驱动；系统 `mhi-bus`、`qrtr-mhi` 继续由 Wi-Fi 依赖选择 |

FM350 的 USB RNDIS 使用 `rndis_host`，USB T99W368 的 MBIM 使用 `cdc_mbim`。本次切换扫描和 AT 设置不代表“拨号成功但无网络”已经真机验证修复。

回归检查：[FM350 自动 APN](../../scripts/tests/test_qmodem_fm350_apn.sh) · [USB 初始化与热插拔](../../scripts/tests/test_qmodem_usb.sh) · [计时与运行源码校验](../../scripts/tests/test_qmodem_clock.sh)。源码校验只允许计时、USB 扫描范围、指定默认值及 FM350 自动 APN 接入，其余运行源码保持官方版本；普通提交不会触发编译。
