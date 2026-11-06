#!/usr/bin/env bash
# 功能：生成 Release 的中文说明和版本信息。
set -euo pipefail
dir="${1:-release}"
test -f "$dir/build-sources.txt"
{
  echo '# 光影猫一代 Pwrt + QModem 自动编译'
  echo
  echo '> 发布流程：构建后先预发布，测试确认后再手动转为正式版本。'
  echo
  echo '> 尚需光影猫一代真机验证，刷机前备份并准备恢复方案。'
  echo
  echo '## 默认网络设置'
  echo
  echo '| 项目 | 默认值 |'
  echo '| --- | --- |'
  echo '| 主机名／界面品牌 | `Pwrt` |'
  echo '| 后台地址 | [http://172.16.0.1](http://172.16.0.1/) |'
  echo '| 后台／SSH 账号 | `root` |'
  echo '| 后台／SSH 密码 | `photonicat` |'
  echo '| 板载 SDIO Wi-Fi 名称 | `Pwrt`（优先 2.4GHz） |'
  echo '| M.2 Wi-Fi 名称 | 5GHz 为 `Pwrt-5G`；2.4GHz 为 `Pwrt-2.4G` |'
  echo '| Wi-Fi 密码／加密 | `photonicat`／WPA2-PSK |'
  echo '| 频段判断顺序 | M.2 单射频优先可用的 5GHz，否则 2.4GHz；双射频支持时分别配置两个频段 |'
  echo '| 5GHz 模式／带宽／信道 | 优先 AX（HE80）／80MHz；驱动检测信道（通常为 36） |'
  echo
  echo '默认值用于首次刷入、恢复出厂或新生成配置；保留配置升级沿用已有网络、无线、root 密码和自定义主机名。'
  echo '固件文件名：Pwrt-P1_年月日时.img.gz（北京时间，SquashFS sysupgrade）。旧更新器不认识短文件名时，请先手动上传升级一次。'
  echo
  echo '## 内置功能'
  echo
  echo '- ImmortalWrt：openwrt-25.12（编译时最新）'
  echo '- QModem：官方 FUjr/QModem stable（Next 界面、短信后台）+ PEIT98/luci-app-qmodem-generic main（自有复刻），mwan3、OpenClash、CPU 调频、电池状态'
  echo '- 网页终端、Aurora 官方主题、多品牌 PCIe Wi-Fi 驱动、iStore、Docker/Compose 与 Dockerman' 
  echo '- 光影猫管理 → 软件包下载源：南京大学、中科大、上海交大、浙江大学、VSEAN 和官方源可选，默认南京大学'
  echo '- NFA765 hw2.1：内置 E108 专用 amss/m3 与板卡修复文件，普通 NFA765 使用原固件'
  echo '- eMMC 自动扩容：利用连续可用空间，保留额外分区及后续升级边界'
  echo '- 系统 → 硬盘保活：默认关闭，仅定时只读选中的 USB 硬盘'
  echo '- 系统 → 在线升级：国内/GitHub 源与正式/预发行通道可选，默认保留配置，仅手动确认后升级'
  echo '- 新增文件管理、Aurora 设置、Travelmate 无线中继（默认关闭）'
  echo '- iStoreOS 官方 QuickStart：首页、网口配置和局域网设备管理'
  echo '- 新增固件版本与 Docker 存储状态卡片'
  echo '- Docker 存储仅检测提示，不会自动挂载、迁移、格式化或修改防火墙' 
  echo '- QModem 使用官方扫描、串口识别、拨号及默认厂商 QMI 驱动；接口名自动生成'
  echo '- mwan3 使用官方默认配置，首启关闭服务；多 WAN 策略按需手动配置'
  echo '- QM 不附加恢复或网络改写脚本；需清除旧 APN 和串口等设置时，刷机请选择不保留配置'
  echo
  echo '<details><summary>源码版本</summary>'
  echo
  echo '~~~'
  cat "$dir/build-sources.txt"
  echo '~~~'
  echo '</details>'
  echo
  if [ -f "$dir/immortalwrt-recent-commits.txt" ]; then
    echo '<details><summary>ImmortalWrt 最近 25 个提交</summary>'
    echo
    echo '~~~'
    cat "$dir/immortalwrt-recent-commits.txt"
    echo '~~~'
    echo '</details>'
    echo
  fi
  for f in "$dir"/*.manifest; do
    [ -f "$f" ] || continue
    echo '<details><summary>内置软件包清单</summary>'
    echo
    echo '~~~'
    cat "$f"
    echo '~~~'
    echo '</details>'
    echo
  done
  echo '<details><summary>SHA256 校验值</summary>'
  echo
  echo '~~~'
  cat "$dir/SHA256SUMS.txt"
  echo '~~~'
  echo '</details>'
} > "$dir/release-notes.md"
