# eMMC 自动扩容与存储

## 自动扩容

固件启动时在挂载 overlay 前按需扩展 eMMC 根分区及文件系统，适配 **1+8、2+16、4+64 GB**。扩展的是存储，运行内存不变。

- 使用根分区后连续可用的空间；遇到额外数据分区即停止，不移动或覆盖其他分区。
- SquashFS 的 F2FS overlay 在挂载前扩展，ext4 同时支持；新配置分区由 fstools 按完整容量初始化。
- 已扩容时不重复操作。需要重新读取分区容量时，首次启动可能额外重启一次，请保持供电。
- 后续同布局升级保留已扩容的根分区边界。镜像中的 1 GiB 为初始大小，不是安装后的容量上限。
- 不限制 Docker 容量，不自动迁移已有数据或自定义目录。

## 配置与数据

存储耗尽时，系统可能无法挂载持久 overlay 而回退到内存配置，表现为设置丢失。出现此情况先检查挂载和空间，不急于重置或格式化：

```sh
df -h /overlay /tmp
mount | grep -E 'overlay|/tmp/root'
logread | grep -E 'mount_root|No space left|f2fs'
```

检查 `/overlay/upper` 是否仍保留原配置，先备份再处理。容器镜像、可写层、数据卷与应用缓存分别核对实际目录；把缓存放入 TF 卡不代表全部 Docker 数据都在卡内。

## 检查范围

提供基于临时 loop 磁盘的回归，用于覆盖 8 / 16 / 64 GiB、实际 64 GB 容量、非整 MiB 容量、F2FS、ext4、额外分区和重启续跑，并核对启动代码、UUID、配置内容及重复执行结果。

来源：SlAlot/ImmortalWrt_Photonicat1 `ae655185`，AGPL-3.0-only。完整许可见 `packages/luci-app-swrt-disk-keepalive/LICENSE`。
