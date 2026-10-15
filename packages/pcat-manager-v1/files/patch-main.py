#!/usr/bin/env python3
"""Patch pinned upstream v1 to stop safely without requesting MCU reboot."""
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()
anchor = "static gboolean pcat_main_sigterm_func(gpointer user_data)"
if s.count(anchor) != 1:
    raise SystemExit("上游 SIGTERM 函数已变更，拒绝补丁")
callback = """static gboolean pcat_main_normal_stop_func(gpointer user_data)
{
    (void)user_data;
    if(g_pcat_main_loop != NULL)
        g_main_loop_quit(g_pcat_main_loop);
    return G_SOURCE_REMOVE;
}

"""
s = s.replace(anchor, callback + anchor, 1)
old = """    else if(!g_pcat_main_watchdog_disabled)
    {
        pcat_main_system_reboot();
    }
"""
new = """    else if(!g_pcat_main_watchdog_disabled)
    {
        g_pcat_main_watchdog_disabled = TRUE;
        pcat_pmu_manager_watchdog_timeout_set(0);
        g_timeout_add(500, pcat_main_normal_stop_func, NULL);
    }
"""
if s.count(old) != 1:
    raise SystemExit("上游 SIGTERM 重启分支已变更，拒绝补丁")
s = s.replace(old, new, 1)
p.write_text(s)
print("已将普通停止操作改为禁用 MCU watchdog 并退出，不再触发整机重启")
