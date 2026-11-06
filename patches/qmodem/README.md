# QModem 修复

QM 计时、开机网卡等待及条件补扫统一放在此目录；基于官方 `stable` 分支，调用官方扫描入口，拨号使用上游逻辑。

Feed 分支由 [scripts/build/prepare.sh](../../scripts/build/prepare.sh) 设置，插件与驱动选项由 [photonicat1.config](../../photonicat1.config) 管理。保留 Next 和 Generic 界面；`stable` 使用 `sms-tool_q` 与 `sms-forwarder-next`，驱动和拨号选择沿用上游的 `luci-app-qmodem_*` 配置名。

| 文件 | 用途 |
| --- | --- |
| [apply.sh](apply.sh) | 构建与源码检查共用的统一入口，应用计时和开机扫描修复 |
| [fix-qmodem-monotonic-clock.sh](fix-qmodem-monotonic-clock.sh) | 使用单调时钟，防止校时回拨卡住扫描队列和超时等待 |
| [fix-qmodem-boot-scan.sh](fix-qmodem-boot-scan.sh) | 将开机等待和条件补扫接入 `qmodem_init`，跳过同次开机的重复预设扫描 |
| [boot-scan.sh](boot-scan.sh) | 等待网卡稳定，调用 `modem_scanc scan all`；未识别时 15 秒后补扫一次 |

从仓库根目录执行：

```sh
sh patches/qmodem/apply.sh immortalwrt/feeds/qmodem
```

保留现有插件、串口、手填 APN、PDP 编号、PCIe 和热插拔配置；APN 处理沿用上游逻辑。公共文本处理函数继续使用 [scripts/lib/patch.sh](../../scripts/lib/patch.sh)。

开机先启动官方扫描守护进程及准备 PCIe 驱动，再异步等待至少 15 秒；已有更长的 `start_delay` 仍生效。随后检查候选网卡是否连续 3 秒稳定，最多额外等 15 秒，再扫描 USB 和 PCIe。首次扫描 15 秒后检查识别结果：没有有效模组，或仍有候选网卡未被识别结果覆盖时，补扫全部总线一次。已识别的模组需具备名称、`enabled` 状态和有效 AT 字符设备；部分识别也会补扫。

`block_auto_probe=1` 时不执行开机扫描；手动启动、重启服务和热插拔沿用上游逻辑。仅替换开机扫描调度，不新增独立服务，不写死槽位。运行片段安装于 `/usr/share/qmodem/fixes/boot-scan.sh`，由 `qmodem_init` 加载。以上是两次全扫描的上限，上游扫描器原有的单个模组探测重试仍保留。

回归检查：[计时与源码校验](../../scripts/tests/test_qmodem_clock.sh) · [开机扫描](../../scripts/tests/test_qmodem_boot_scan.sh)。源码校验仅允许计时、开机入口及指定扫描片段，拨号脚本及其余运行源码保持官方版本。`apply.sh` 及 `fix-*.sh` 仅在构建主机执行；普通提交不会启动编译。
