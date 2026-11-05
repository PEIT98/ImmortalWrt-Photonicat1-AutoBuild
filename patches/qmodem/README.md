# QModem 计时与启动扫描修复

QM 计时、启动扫描修复及插入片段统一放在此目录。

| 文件 | 用途 |
| --- | --- |
| [apply.sh](apply.sh) | 构建与源码检查共用的统一入口，按顺序应用下面两项修复 |
| [fix-qmodem-monotonic-clock.sh](fix-qmodem-monotonic-clock.sh) | 使用单调时钟，防止校时回拨卡住扫描队列和超时等待 |
| [fix-qmodem-boot-scan.sh](fix-qmodem-boot-scan.sh) | 网卡和扫描后台就绪后扫描，15 秒后仍未识别才补扫一次 |
| [boot-usb-scan.sh](boot-usb-scan.sh) | 供启动扫描修复插入 QM 原有启动脚本的函数片段，不单独运行 |

从仓库根目录执行：

```sh
sh patches/qmodem/apply.sh immortalwrt/feeds/qmodem
```

保留现有插件、串口、APN、拨号、PCIe 和热插拔配置。公共文本处理函数继续使用 [scripts/lib/patch.sh](../../scripts/lib/patch.sh)。

回归检查：[计时与源码校验](../../scripts/tests/test_qmodem_clock.sh) · [启动扫描](../../scripts/tests/test_qmodem_boot_scan.sh)。修复脚本仅在构建主机执行；普通提交不会启动编译。
