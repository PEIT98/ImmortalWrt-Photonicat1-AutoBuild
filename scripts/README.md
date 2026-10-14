# 构建脚本（中文功能说明）

此目录按 **构建管理** 和 **兼容补丁** 分类。脚本保持英文文件名以兼容 Linux 路径和 GitHub Actions。

## build：构建管理

| 脚本 | 作用 |
| --- | --- |
| [prepare.sh](build/prepare.sh) | 继承光影猫参考配置，准备软件源、内核补丁和覆盖文件 |
| [select-packages.py](build/select-packages.py) | 在安装 Feeds 后读取独立配置，选择插件和驱动 |
| [verify-config.sh](build/verify-config.sh) | 检查目标设备、插件、驱动和依赖；缺少必要配置则停止 |
| [release-notes.sh](build/release-notes.sh) | 生成 GitHub Release 中文说明和编译来源信息 |

## patches：兼容补丁

| 脚本 | 作用 |
| --- | --- |
| [enable-qca9377-ath10k-sdio.py](patches/enable-qca9377-ath10k-sdio.py) | 保留 PCIe ath10k，同时为板载 QCA9377 加入 SDIO 驱动 |
| [fix-aurora-battstatus.py](patches/fix-aurora-battstatus.py) | 修复 Aurora 下的电池指示，不改主题源码 |
| [fix-istore-25.12.sh](patches/fix-istore-25.12.sh) | 修复 iStore 包名与 taskd 依赖检查 |
| [hide-mwan3-status-menu.py](patches/hide-mwan3-status-menu.py) | 隐藏状态页重复 mwan3 菜单，保留网络页入口 |
| [wifi-band-order.sh](patches/wifi-band-order.sh) | 使用上游 Wi-Fi 脚本并调整频段显示顺序 |

## 配置来源与构建顺序

1. `build/prepare.sh` 继承参考设备配置，并加载兼容补丁。
2. 更新 Feeds 后，`build/select-packages.py` 应用根目录 `photonicat1.config` 的覆盖项。
3. 运行 `make defconfig`，再由 `build/verify-config.sh` 检查依赖。
4. 编译成功后用 `build/release-notes.sh` 生成发布说明。

**配置文件区别：** `photonicat1.config` 只保存需要覆盖的配置；完整 `immortalwrt/.config` 在编译期间生成，并上传至 Actions 的 `photonicat1-build-config` Artifact。无需将旧版完整配置拷入仓库。

**编译触发：** 仅通过 Actions 手动 `Run workflow` 编译。保留所有插件、系统配置、源码缓存及 CCache。
