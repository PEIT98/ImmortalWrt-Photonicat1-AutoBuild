# QModem 修复

QM 计时及 FM350 自动 APN 修复统一放在此目录；基于官方 `stable` 分支，启动扫描使用官方逻辑。

Feed 分支由 [scripts/build/prepare.sh](../../scripts/build/prepare.sh) 设置，插件与驱动选项由 [photonicat1.config](../../photonicat1.config) 管理。保留 Next 和 Generic 界面；`stable` 使用 `sms-tool_q` 与 `sms-forwarder-next`，驱动和拨号选择沿用上游的 `luci-app-qmodem_*` 配置名。

| 文件 | 用途 |
| --- | --- |
| [apply.sh](apply.sh) | 构建与源码检查共用的统一入口，按顺序应用下面两项修复 |
| [fix-qmodem-monotonic-clock.sh](fix-qmodem-monotonic-clock.sh) | 使用单调时钟，防止校时回拨卡住扫描队列和超时等待 |
| [fix-fm350-auto-apn.sh](fix-fm350-auto-apn.sh) | 为官方拨号脚本增加 FM350 APN 补全入口，并将片段打入 qmodem 包 |
| [fm350-auto-apn.sh](fm350-auto-apn.sh) | 仅处理 `fm350` / `fm350-gl`：手填优先；自动时读取当前 PDP 的数据 APN，排除 IMS 等配置，再按 SIM 运营商兜底 |

从仓库根目录执行：

```sh
sh patches/qmodem/apply.sh immortalwrt/feeds/qmodem
```

保留现有插件、串口、手填 APN、PDP 编号、PCIe 和热插拔配置。自动补全只改变 FM350 当前拨号进程中的 APN，不写入 UCI，界面仍显示自动；其他型号直接跳过。公共文本处理函数继续使用 [scripts/lib/patch.sh](../../scripts/lib/patch.sh)。

固件中补全片段位于 `/usr/share/qmodem/fixes/fm350-auto-apn/auto-apn.sh`，由 `/usr/share/qmodem/modem_dial.sh` 的 `at_dial()` 入口加载，不新增服务或扫描脚本。

回归检查：[计时与源码校验](../../scripts/tests/test_qmodem_clock.sh) · [FM350 APN](../../scripts/tests/test_qmodem_fm350_apn.sh)。`apply.sh` 及 `fix-*.sh` 仅在构建主机执行；普通提交不会启动编译。
