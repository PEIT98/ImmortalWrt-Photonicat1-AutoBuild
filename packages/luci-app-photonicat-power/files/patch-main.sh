#!/bin/sh
# 构建主机脚本：先校验，再提交全部文本修改。
set -eu
. "$(dirname "$0")/patch-common.sh"
pc_init
pc_load "${1:?需要 main.c 路径}"
pc_replace 'static gboolean pcat_main_sigterm_func(gpointer user_data)' 'static gboolean pcat_main_normal_stop_func(gpointer user_data)
{
    (void)user_data;
    if(g_pcat_main_loop != NULL)
        g_main_loop_quit(g_pcat_main_loop);
    return G_SOURCE_REMOVE;
}

static gboolean pcat_main_sigterm_func(gpointer user_data)' 'SIGTERM 回调'
pc_replace '    else if(!g_pcat_main_watchdog_disabled)
    {
        pcat_main_system_reboot();
    }
' '    else if(!g_pcat_main_watchdog_disabled)
    {
        g_pcat_main_watchdog_disabled = TRUE;
        pcat_pmu_manager_watchdog_timeout_set(0);
        g_timeout_add(500, pcat_main_normal_stop_func, NULL);
    }
' 'SIGTERM 停止分支'
pc_commit
echo "已将普通停止改为禁用 MCU watchdog 并退出"
