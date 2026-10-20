#!/usr/bin/env python3
"""只为光影猫一代调整 MCU 服务默认包，其它设备配置不变。"""
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
match = re.search(r"(^define Device/ariaboard_photonicat\n)(.*?)(^endef\s*$)", text, re.M | re.S)
if not match:
    raise SystemExit("找不到 Photonicat1 设备定义，拒绝继续")
section = match.group(2)
if section.count("pcat-mgr") != 1:
    raise SystemExit("Photonicat1 默认包中 pcat-mgr 的数量不正确")
section = section.replace("pcat-mgr", "luci-app-photonicat-power")
path.write_text(text[:match.start(2)] + section + text[match.end(2):])
print("Photonicat1 默认 MCU 守护进程已并入 luci-app-photonicat-power")
