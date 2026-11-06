# 脚本分类与用途

这里的脚本在构建主机执行，由 [GitHub Actions](../.github/workflows/build.yml) 按顺序调用。生产脚本使用 Shell；测试使用 Bash 或 Node.js。上游工具链需要的 Python 依赖仍然保留。

## 目录索引

| 目录 | 用途 |
| --- | --- |
| [build/](build/) | 准备源码、选择软件包、内置固件和内核文件 |
| [checks/](checks/) | 检查配置、软件源和真实源码编译结果 |
| [release/](release/) | 写入固件身份、生成发布说明 |
| [patches/wireless/](patches/wireless/) | 无线驱动与默认频段补丁脚本 |
| [patches/storage/](patches/storage/) | eMMC 扩容及升级兼容补丁脚本 |
| [patches/packages/](patches/packages/) | 软件包名称、依赖和编译兼容修复脚本 |
| [lib/](lib/) | 公共文本补丁函数，不单独运行 |
| [tests/](tests/) | 回归测试；`fixtures/` 为测试数据，`common.sh` 和 `disk_keepalive_harness.sh` 为测试辅助文件 |

补丁原文件与插入片段统一放在根目录 [patches/](../patches/README.md)；QM 计时、原生 USB 扫描适配和默认值集中在 [patches/qmodem/](../patches/qmodem/README.md)。插件内部脚本保留在各自 `packages/` 中；设备开机脚本保留在 `files/` 的系统路径中。

## 构建、检查与发布

| 分类 | 脚本 | 作用 |
| --- | --- | --- |
| 构建 | [prepare.sh](build/prepare.sh) | 继承设备参考配置，准备 Feeds、本地插件、覆盖文件和补丁 |
| 构建 | [install-istore-quickstart.sh](build/install-istore-quickstart.sh) | 获取 LinkEase 官方 QuickStart 前后端，检查首页、网口及局域网设备路由和接口 |
| 构建 | [select-packages.sh](build/select-packages.sh) | Feeds 安装后应用根目录 `photonicat1.config` 的覆盖项 |
| 构建 | [bundle-nfa765-e108.sh](build/bundle-nfa765-e108.sh) | 校验并内置 E108 专用固件，安装对应 ath11k 补丁 |
| 构建 | [bundle-openclash-core.sh](build/bundle-openclash-core.sh) | 获取、验证并内置 OpenClash Meta 内核 |
| 检查 | [verify-config.sh](checks/verify-config.sh) | `make defconfig` 后检查目标、插件、驱动和必选依赖 |
| 检查 | [verify-qmodem-feeds.sh](checks/verify-qmodem-feeds.sh) | 检查 QM/Generic 依赖、菜单冲突，运行源码只允许指定计时和 USB 适配 |
| 检查 | [check-qmodem-ndisc6-build.sh](checks/check-qmodem-ndisc6-build.sh) | 检查 ndisc6 归档 SHA256、musl 编译和程序安装 |
| 发布 | [stamp-firmware.sh](release/stamp-firmware.sh) | 为在线升级和 Release 写入相同的设备、标签和提交号 |
| 发布 | [release-notes.sh](release/release-notes.sh) | 生成中文发布说明、源码信息和校验值 |

## 补丁脚本

| 分类 | 脚本 | 作用 |
| --- | --- | --- |
| 无线 | [enable-qca9377-ath10k-sdio.sh](patches/wireless/enable-qca9377-ath10k-sdio.sh) | 为板载 QCA9377 加入 SDIO 支持，同时保留 PCIe |
| 无线 | [wifi-band-order.sh](patches/wireless/wifi-band-order.sh) | 板载使用 `Pwrt`；M.2 优先可用 5GHz，双射频支持时分别配置两个频段 |
| 存储 | [enable-emmc-autogrow.sh](patches/storage/enable-emmc-autogrow.sh) | 修补 Rockchip 镜像检查与刷写流程，保留已扩大的根分区 |
| 软件包 | [fix-istore-25.12.sh](patches/packages/fix-istore-25.12.sh) | 显式固定 iStore 包名并检查 taskd 等依赖 |
| 软件包 | [fix-luajit-riscv-provider.sh](patches/packages/fix-luajit-riscv-provider.sh) | 在 armv8/aarch64 上修复 LuaJIT 虚拟包自依赖 |
| 软件包 | [fix-qmodem-ndisc6-source.sh](patches/packages/fix-qmodem-ndisc6-source.sh) | 修复已知旧版 ndisc6 的下载与编译兼容 |
| QModem | [统一修复入口](../patches/qmodem/apply.sh) | 集中应用计时、原生 USB 扫描适配及西瓜皮 AT 默认值；文件均位于 [patches/qmodem/](../patches/qmodem/README.md) |
| 软件包 | [fix-weechat-provider.sh](patches/packages/fix-weechat-provider.sh) | 使用已有的 WeeChat 默认提供者，避免 Kconfig 自递归 |

[lib/patch.sh](lib/patch.sh) 提供源码锚点检查、临时副本修改与写回函数。电源插件内的 `patch-common.sh` 保持独立副本，插件复制到源码树后可以自行构建。

## 调用顺序

1. `build/prepare.sh` 准备参考配置、本地插件、TD-TECH、存储与无线默认值。
2. 启用板载 SDIO；更新 Feeds 后处理 LuaJIT、ndisc6、WeeChat 兼容，验证并修复 QM 计时与开机扫描，再刷新索引并安装 Feeds。
3. 检查 QM/Generic，处理 iStore 包名；`build/select-packages.sh` 应用插件选择。
4. 执行 `make defconfig`，由 `checks/verify-config.sh` 检查，再生成固件身份、内置文件并下载源码。
5. 检查 ndisc6，准备构建工具并显式构建主机 `ucode`，验证无线默认值后再编译固件，收集短文件名镜像并生成发布说明。

编译仅由 Actions 手动触发；普通提交不会启动编译。完整 `.config` 由流程生成并上传为 `photonicat1-build-config`，根目录仅维护覆盖配置。

## iStoreOS QuickStart

仅编译时从 LinkEase 官方拉取 UI 和后端两个包，安装到编译树的 `package/luci-app-quickstart`、`package/quickstart`。首页包含局域网设备管理入口（`/admin/quickstart/devicemanagement`），构建脚本检查页面路由与设备列表 API；启动保护在 `files/etc/uci-defaults/98-pwrt-quickstart-safe`，禁用自动 `uciChange` 服务 `startdhns`，不影响手动网口管理。选择项在 `photonicat1.config`，校验项在 `checks/verify-config.sh`。

## 回归测试

| 范围 | 测试入口 |
| --- | --- |
| 构建与依赖 | [test_build_scripts.sh](tests/test_build_scripts.sh)、[test_build_dependencies.sh](tests/test_build_dependencies.sh) |
| QM 扫描计时 | [test_qmodem_clock.sh](tests/test_qmodem_clock.sh)；需要官方 QM Feed、C 编译器和 json-c 开发库 |
| QM USB 初始化 | [test_qmodem_usb.sh](tests/test_qmodem_usb.sh)；检查原生延时扫描、PCIe Wi-Fi 排除、AT 默认值、TD-TECH 例外和补丁失败保护 |
| 无线与固件 | [test_wifi_defaults.sh](tests/test_wifi_defaults.sh)、[test_nfa765_e108.sh](tests/test_nfa765_e108.sh)；需要对应 ImmortalWrt 源码树 |
| eMMC 与升级分区 | [test_autogrow.sh](tests/test_autogrow.sh)、[test_storage_integration.sh](tests/test_storage_integration.sh)、[test_autogrow_real.sh](tests/test_autogrow_real.sh) |
| USB 硬盘保活 | [test_disk_keepalive.sh](tests/test_disk_keepalive.sh)、[前端测试](tests/test_disk_keepalive_frontend.cjs) |
| 在线升级 | [test_online_upgrade.sh](tests/test_online_upgrade.sh)、[前端测试](tests/test_online_upgrade_frontend.js) |
| 电源界面与软件源 | [顶部状态](tests/test_photonicat_header.js)、[状态后台](tests/test_photonicat_header_backend.js)、[软件源后台](tests/test_package_sources.sh)、[软件源前端](tests/test_package_sources_frontend.js) |

从仓库根目录运行，例如：

```bash
bash scripts/tests/test_build_scripts.sh
bash scripts/tests/test_build_dependencies.sh
bash scripts/tests/test_autogrow.sh
bash scripts/tests/test_storage_integration.sh
bash scripts/tests/test_online_upgrade.sh
```

真实分区扩容和 USB 磁盘测试使用临时磁盘，需要 root、loop 设备及相关文件系统工具；完整环境由 Actions 准备。

## 设备默认值与插件

网络、品牌和无线名称见 [首页](../README.md#默认网络设置)。保留配置升级时沿用已有网络、无线、密码和自定义主机名。QM 使用西瓜皮的原生 15 秒延时扫描及 AT 工具设置，扫描和网卡热插拔仅处理 USB 模组；TD-TECH 保留 `tom_modem` 例外，不关闭拨号。旧网卡稳定等待和条件补扫已移除，计时修复保留；USB 拨号、串口探测及热插拔时序沿用上游逻辑。模组 PCIe 驱动关闭，PCIe Wi-Fi 及依赖保留。ndisc6 保留构建兼容修复。独立菜单文件将显示名称设为“移动网络”。mwan3 保留上游默认配置，首启关闭服务及自启动。

本地插件完整源码位于 [packages/](../packages/)；电源与软件源设置、CPU 调频、在线升级和硬盘保活的说明见首页对应链接。文件管理和 Travelmate 使用官方软件源；Aurora 设置使用主题作者源码。

Aurora 更新源由 [99-aurora-update-source](../files/etc/uci-defaults/99-aurora-update-source) 在首启时登记：使用配置插件自带签名公钥，默认添加作者的 APK snapshots 源；已有 Aurora 源和其他软件源保持原样。首启不联网刷新索引，需要升级时在软件包页面更新列表。

