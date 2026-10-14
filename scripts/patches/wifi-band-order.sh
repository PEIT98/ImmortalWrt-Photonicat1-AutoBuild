#!/bin/sh
# 功能：修正 Wi-Fi 频段显示顺序。
# 参考西瓜皮脚本的频段排序修正，但使用当前 ImmortalWrt 自己的 mac80211.uc 源码。
set -eu
SRC="${1:?需要 ImmortalWrt 根目录}"
FROM="$SRC/package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
TO="$SRC/files/lib/wifi/mac80211.uc"
[ -f "$FROM" ] || { echo '::warning::找不到 mac80211.uc，保留上游默认值' >&2; exit 0; }
mkdir -p "$(dirname "$TO")"
python3 - "$FROM" "$TO" <<'PY'
from pathlib import Path
import re, sys
src, dest = map(Path, sys.argv[1:3])
data = src.read_text()
pattern = r'^const bands_order\s*=\s*\[[^\n]*\];'
match = re.search(pattern, data, re.M)
if not match:
    print('::warning::上游 mac80211.uc 未发现 bands_order，跳过排序覆盖')
else:
    updated = data[:match.start()] + 'const bands_order = [ "2G", "5G", "6G", "60G" ];' + data[match.end():]
    dest.write_text(updated)
    print('Wi-Fi 首次配置优先顺序：2G -> 5G -> 6G -> 60G')
PY
