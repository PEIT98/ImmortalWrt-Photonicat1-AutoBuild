# QModem 修复

QM 计时修复统一放在此目录；基于官方 `stable` 分支，启动扫描和拨号使用官方逻辑。

Feed 分支由 [scripts/build/prepare.sh](../../scripts/build/prepare.sh) 设置，插件与驱动选项由 [photonicat1.config](../../photonicat1.config) 管理。保留 Next 和 Generic 界面；`stable` 使用 `sms-tool_q` 与 `sms-forwarder-next`，驱动和拨号选择沿用上游的 `luci-app-qmodem_*` 配置名。

| 文件 | 用途 |
| --- | --- |
| [apply.sh](apply.sh) | 构建与源码检查共用的统一入口，应用计时修复 |
| [fix-qmodem-monotonic-clock.sh](fix-qmodem-monotonic-clock.sh) | 使用单调时钟，防止校时回拨卡住扫描队列和超时等待 |

从仓库根目录执行：

```sh
sh patches/qmodem/apply.sh immortalwrt/feeds/qmodem
```

保留现有插件、串口、手填 APN、PDP 编号、PCIe 和热插拔配置；APN 处理沿用上游逻辑。公共文本处理函数继续使用 [scripts/lib/patch.sh](../../scripts/lib/patch.sh)。

回归检查：[计时与源码校验](../../scripts/tests/test_qmodem_clock.sh)。源码校验仅允许计时修复，拨号脚本及其余运行源码保持官方版本。`apply.sh` 及 `fix-*.sh` 仅在构建主机执行；普通提交不会启动编译。
