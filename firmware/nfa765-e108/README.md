# NFA765 / WCN6855 hw2.1 E108 固件

仅为 PCI `17cb:1103`、子设备 `105b:e108`、硬件版本 WCN6855 hw2.1 选择专用固件。普通 NFA765 和其他 WCN6855 沿用原有驱动路径及板卡文件，已有设备树 `firmware-name` 设置优先保留。

## 内置文件

| 文件 | 来源与用途 |
| --- | --- |
| `amss.bin`、`m3.bin` | 用户指定 linux-firmware 的 `ath11k/WCN6855/hw2.0/nfa765` 固件，固定提交 `273e26348fbd4c14320f6789e999b3211e696690`；版本 `WLAN.HSP.1.1-04866.5-QCAHSPSWPL_V1_V2_SILICONZ_IOE-1` |
| `board-2.bin` | 之前验证的 E108 修复文件，SHA256 为 `ded4d57897bff49de5af7434e66c294a456c06b2165c207331cab3e209f3ae9d`；包括 `qmi-chip-id=2/18`、`qmi-board-id=255` |
| `Notice.txt`、`LICENSE.QualcommAtheros_ath10k` | 上游固件通知与再分发许可 |
| `SHA256SUMS`、`build-info` | 固件校验值、适用硬件与上游版本记录 |

仓库内以 `board-2.bin.gz` 保存原修复文件，构建时解压并验证。主固件和通知由 [构建脚本](../../scripts/build/bundle-nfa765-e108.sh) 从固定的 [linux-firmware 提交](https://kernel.googlesource.com/pub/scm/linux/kernel/git/firmware/linux-firmware/+/273e26348fbd4c14320f6789e999b3211e696690/ath11k/WCN6855/hw2.0/nfa765/) 获取，校验后随镜像发布；路由器启动时离线使用。

## 路径与兼容

设备加载路径为 `/lib/firmware/ath11k/WCN6855/hw2.1/nfa765-e108/`。保留上游 `hw2.1 -> ./hw2.0` 链接，因此实际文件放在 `hw2.0/nfa765-e108/` 私有子目录；hw2.0 与 hw2.1 的默认 `amss.bin`、`m3.bin`、`board-2.bin` 和法规数据均不覆盖。

[ath11k 补丁](../../patches/ath11k/999-photonicat-nfa765-e108-firmware.patch) 在读取设备树设置后，仅为上述 E108 硬件选择私有目录中的主固件和板卡文件；预留的 `firmware-2.bin` 请求也走私有目录，文件不存在时按上游流程回退到 amss/m3。其他板卡继续执行原始路径选择逻辑，包括上游的 usecase 选择；不修改无线频段、带宽、信道或监管设置。

旧 E108 板卡文件仅含 E108 的配置，不能直接覆盖所有卡共用的 `board-2.bin`。本适配将其隔离，保留普通卡所需的全部上游板卡数据；不添加设备端下载、覆盖或重启脚本。

构建流水线校验下载、补丁和实际 backports C 函数，并测试普通卡路径、硬件版本、设备树覆盖、目录链接、重复执行及下载失败保护。真机冷启动、AP/STA 与具体频宽仍需刷入后验证。
