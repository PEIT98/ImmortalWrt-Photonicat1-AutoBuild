#!/usr/bin/env bash
# 功能：生成 Release 的中文说明和版本信息。
set -euo pipefail
dir="${1:-release}"
test -f "$dir/build-sources.txt"
{
  echo '# 光影猫一代 ImmortalWrt + QModem 自动编译'
  echo
  echo '> 发布流程：构建后先预发布，测试确认后再手动转为正式版本。'
  echo
  echo '> 尚需光影猫一代真机验证，刷机前备份并准备恢复方案。'
  echo
  echo '- ImmortalWrt：openwrt-25.12（编译时最新）'
  echo '- QModem：官方 FUjr/QModem main（Next 界面、短信后台）+ PEIT98/luci-app-qmodem-generic main（自有复刻），mwan3、OpenClash、CPU 调频、电池状态'
  echo '- 网页终端、Aurora 官方主题、多品牌 PCIe Wi-Fi 驱动、iStore、Docker/Compose 与 Dockerman' 
  echo '- 系统 → 在线升级：默认检查本仓库光影猫固件，下载后校验文件和机型，仅手动确认后升级'
  echo '- 新增文件管理、Aurora 设置、历史统计、Travelmate 无线中继（默认关闭）'
  echo '- 内置 SQM/CAKE 与 cake-autorate 稳定版，默认关闭；先填写实测速率并配置队列，再手动开启'
  echo '- 新增固件版本与 Docker 存储状态卡片、Bandix Plus 多接口流量统计（首次默认关闭）' 
  echo '- Docker 存储仅检测提示，不会自动挂载、迁移、格式化或修改防火墙' 
  echo '- 优先级：WAN > Wi-Fi 中继 > 5G/LTE'
  echo '- 首次配置 Wi-Fi STA/wwan 和 QModem APN；5G 拨号接口自动识别，无需固定别名'
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
