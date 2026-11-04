#!/bin/sh
# 构建主机脚本：先校验，再提交全部文本修改。
set -eu
. "$(dirname "$0")/patch-common.sh"
pc_init
pc_load "${1:?需要 pmu-manager.c 路径}"
pc_replace '    gboolean last_on_battery_state;
    guint last_battery_percentage;' '    gboolean last_on_battery_state;
    gboolean external_power_seen_in_ups_mode;
    guint last_battery_percentage;' '状态字段'
pc_replace '    now = g_get_monotonic_time();
    if(pmu_data->last_charger_voltage >= charge_detection_threshold)
    {
        pmu_data->charger_on_auto_start_last_timestamp = now;
    }' '    now = g_get_monotonic_time();
    if(pmu_data->last_charger_voltage >= charge_detection_threshold)
    {
        pmu_data->charger_on_auto_start_last_timestamp = now;
        if(pcat_main_user_config_data_get()->charger_on_auto_start)
            pmu_data->external_power_seen_in_ups_mode = TRUE;
    }' '供电检测'
pc_replace 'if((pmu_data->power_on_event==3 || pmu_data->power_on_event==4) &&
               now > pmu_data->charger_on_auto_start_last_timestamp +' 'if((pmu_data->power_on_event==3 || pmu_data->power_on_event==4 ||
                pmu_data->external_power_seen_in_ups_mode) &&
               now > pmu_data->charger_on_auto_start_last_timestamp +' '车载模式触发条件'
pc_replace 'void pcat_pmu_manager_charger_on_auto_start(gboolean state)
{
    if(!g_pcat_pmu_manager_data.initialized)
    {
        return;
    }

    pcat_pmu_manager_charger_on_auto_start_internal(' 'void pcat_pmu_manager_charger_on_auto_start(gboolean state)
{
    if(!g_pcat_pmu_manager_data.initialized)
    {
        return;
    }

    /* Re-arm monitoring whenever user switches UPS mode. No shutdown
     * for a manually booted device that never saw external power. */
    g_pcat_pmu_manager_data.external_power_seen_in_ups_mode = FALSE;
    g_pcat_pmu_manager_data.charger_on_auto_start_last_timestamp =
        g_get_monotonic_time();

    pcat_pmu_manager_charger_on_auto_start_internal(' '模式切换重新计时'
pc_commit
echo "已保留车载 UPS 模式与拔电倒计时"
