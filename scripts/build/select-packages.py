#!/usr/bin/env python3
# 功能：读取独立配置，保留参考固件的其他选项。
"""安装 Feeds 后应用独立插件配置，保留参考设备的其他选项。"""
from pathlib import Path
import re
import sys

p = Path(sys.argv[1])
overrides_file = Path(__file__).resolve().parent.parent.parent / "photonicat1.config"
original = p.read_text()
if not overrides_file.is_file():
    raise SystemExit(f"Missing package override file: {overrides_file}")

overrides = {}
for lineno, raw in enumerate(overrides_file.read_text().splitlines(), 1):
    line = raw.strip()
    if not line or (line.startswith("#") and not line.startswith("# CONFIG_")):
        continue
    enabled = re.fullmatch(r'(CONFIG_[A-Za-z0-9_+.-]+)=(y|m|n|".*")', line)
    disabled = re.fullmatch(r'# (CONFIG_[A-Za-z0-9_+.-]+) is not set', line)
    if not enabled and not disabled:
        raise SystemExit(f"{overrides_file}:{lineno}: invalid config entry: {line}")
    key = (enabled or disabled).group(1)
    if key in overrides:
        raise SystemExit(f"{overrides_file}:{lineno}: duplicate config key: {key}")
    overrides[key] = line

# 参考配置可能残留 PassWall 子选项；只关闭这些子选项，不改变其他插件。
passwall_prefix = "CONFIG_PACKAGE_luci-app-passwall_INCLUDE_"
removed_passwall = set()
kept = []
for line in original.splitlines():
    m = re.match(r'^(?:# )?(CONFIG_[A-Za-z0-9_+.-]+)(?:=| is not set)', line)
    if m:
        key = m.group(1)
        if key in overrides:
            continue
        if key.startswith(passwall_prefix):
            removed_passwall.add(key)
            continue
    kept.append(line)

kept.extend(["", "# Photonicat1 configuration overrides (photonicat1.config)"])
for key in sorted(removed_passwall - overrides.keys()):
    kept.append(f"# {key} is not set")
for key in sorted(overrides):
    kept.append(overrides[key])
p.write_text("\n".join(kept) + "\n")
print(f"Applied {len(overrides)} Photonicat1 config overrides; "
      f"disabled {len(removed_passwall)} legacy PassWall sub-options")
