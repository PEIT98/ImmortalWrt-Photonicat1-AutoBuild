#!/usr/bin/env python3
# 功能：隐藏状态页重复的 mwan3 菜单，保留网络设置入口。
"""仅隐藏“状态→MultiWAN”重复菜单，保留“网络→MultiWAN”入口；在编译 LuCI 软件包前修改 Feed 文件。"""
import json
import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("Usage: hide-mwan3-status-menu.py IMMORTALWRT_ROOT")

menu_file = (Path(sys.argv[1]) / "feeds/luci/applications/luci-app-mwan3"
             / "root/usr/share/luci/menu.d/luci-app-mwan3.json")
if not menu_file.is_file():
    raise SystemExit(f"ERROR: upstream LuCI mwan3 menu was not found: {menu_file}")

menu = json.loads(menu_file.read_text(encoding="utf-8"))
if not isinstance(menu, dict) or "admin/network/mwan3" not in menu:
    raise SystemExit("ERROR: mwan3 network menu changed upstream; refusing unsafe edit")

status_keys = [name for name in menu if name == "admin/status/mwan3"
               or name.startswith("admin/status/mwan3/")]
network_keys_before = {name: entry for name, entry in menu.items()
                       if name == "admin/network/mwan3"
                       or name.startswith("admin/network/mwan3/")}
if not status_keys:
    print("Status > MultiWAN already absent; Network > MultiWAN preserved")
    sys.exit(0)

for name in status_keys:
    del menu[name]
network_keys_after = {name: entry for name, entry in menu.items()
                      if name == "admin/network/mwan3"
                      or name.startswith("admin/network/mwan3/")}
if network_keys_before != network_keys_after:
    raise SystemExit("ERROR: network-side mwan3 menu changed unexpectedly")

menu_file.write_text(json.dumps(menu, ensure_ascii=False, indent="\t") + "\n",
                     encoding="utf-8")
print(f"Removed {len(status_keys)} Status > MultiWAN menu entries; "
      f"preserved {len(network_keys_after)} Network > MultiWAN entries")
