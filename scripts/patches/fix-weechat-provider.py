#!/usr/bin/env python3
"""Use the real default WeeChat provider, avoiding a virtual-package cycle."""
from pathlib import Path
import re
import sys


def prepare(root):
    root = Path(root)
    recipe = root / "feeds/luci/applications/luci-app-weechat/Makefile"
    if not recipe.exists():
        print("WeeChat frontend is absent; no provider patch needed")
        return
    source = recipe.read_text()
    virtual = re.compile(r"(?<!\S)\+weechat(?=\s|$)")
    count = len(virtual.findall(source))
    if not count:
        print("WeeChat already uses a concrete provider")
        return
    provider = root / "feeds/packages/net/weechat/Makefile"
    if count != 1 or not provider.exists() or "define Package/weechat-minimal" not in provider.read_text():
        raise ValueError("WeeChat provider layout changed; review before resolving dependencies")
    recipe.write_text(virtual.sub("+weechat-minimal", source, count=1))
    print("WeeChat: selected concrete default weechat-minimal provider")


if __name__ == "__main__":
    prepare(sys.argv[1])
