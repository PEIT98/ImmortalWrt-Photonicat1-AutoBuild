# QModem 修复

QM 计时、启动扫描及 FM350 自动 APN 修复统一放在此目录。

| 文件 | 用途 |
| --- | --- |
| [apply.sh](apply.sh) | 构建与源码检查共用的统一入口，按顺序应用下面三项修复 |
| [fix-qmodem-monotonic-clock.sh](fix-qmodem-monotonic-clock.sh) | 使用单调时钟，防止校时回拨卡住扫描队列和超时等待 |
| [fix-qmodem-boot-scan.sh](fix-qmodem-boot-scan.sh) | 网卡和扫描后台就绪后扫描，15 秒后仍未识别才补扫一次 |
| [boot-usb-scan.sh](boot-usb-scan.sh) | 供启动扫描修复插入 QM 原有启动脚本的函数片段，不单独运行 |
| [fix-fm350-auto-apn.sh](fix-fm350-auto-apn.sh) | 为官方拨号脚本增加 FM350 APN 补全入口，并将片段打入 qmodem 包 |
| [fm350-auto-apn.sh](fm350-auto-apn.sh) | 仅处理 `fm350` / `fm350-gl`：手填优先；自动时读取当前 PDP 的数据 APN，排除 IMS 等配置，再按 SIM 运营商兜底 |

从仓库根目录执行：

```sh
sh patches/qmodem/apply.sh immortalwrt/feeds/qmodem
```

保留现有插件、串口、手填 APN、PDP 编号、PCIe 和热插拔配置。自动补全只改变 FM350 当前拨号进程中的 APN，不写入 UCI，界面仍显示自动；其他型号直接跳过。公共文本处理函数继续使用 [scripts/lib/patch.sh](../../scripts/lib/patch.sh)。

固件中补全片段位于 `/usr/share/qmodem/fixes/fm350-auto-apn/auto-apn.sh`，由 `/usr/share/qmodem/modem_dial.sh` 的 `at_dial()` 入口加载，不新增服务或扫描脚本。

回归检查：[计时与源码校验](../../scripts/tests/test_qmodem_clock.sh) · [启动扫描](../../scripts/tests/test_qmodem_boot_scan.sh) · [FM350 APN](../../scripts/tests/test_qmodem_fm350_apn.sh)。`apply.sh` 及 `fix-*.sh` 仅在构建主机执行；普通提交不会启动编译。
