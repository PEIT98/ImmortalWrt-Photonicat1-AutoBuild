#!/usr/bin/env bash
set -euo pipefail
dir="${1:-release}"
test -f "$dir/build-sources.txt"
{
  echo '# 光影猫一代 ImmortalWrt + QModem 自动编译'
  echo
  echo '> 尚需光影猫一代真机验证，刷机前备份并准备恢复方案。'
  echo
  echo '- ImmortalWrt：openwrt-25.12（编译时最新）'
  echo '- QModem Next（短信）、mwan3、Clash、CPU 调频、电池状态'
  echo '- 优先级：WAN > Wi-Fi 中继 > 5G/LTE'
  echo '- 首次需配置 Wi-Fi STA/wwan 与 QModem 别名 wwan_5g'
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
