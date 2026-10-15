#!/usr/bin/env python3
"""允许光影猫一代从外部供电切换到电池后，按车载/UPS 模式延时关机。

严格锁定上游 v1 的代码锚点，不改串口、网络或 QModem。
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-photonicat-ups.py path/to/pmu-manager.c")
path = Path(sys.argv[1])
s = path.read_text()

def patch_once(old, new, name):
    global s
    if s.count(old) != 1:
        raise SystemExit(f"光影猫 UPS 补丁失败：{name} 上游结构已变化，拒绝继续")
    s = s.replace(old, new, 1)

patch_once(
    "    gboolean last_on_battery_state;\n    guint last_battery_percentage;",
    "    gboolean last_on_battery_state;\n"
    "    gboolean external_power_seen_in_ups_mode;\n"
    "    guint last_battery_percentage;",
    "状态字段",
)
patch_once(
    "    now = g_get_monotonic_time();\n"
    "    if(pmu_data->last_charger_voltage >= charge_detection_threshold)\n"
    "    {\n"
    "        pmu_data->charger_on_auto_start_last_timestamp = now;\n"
    "    }",
    "    now = g_get_monotonic_time();\n"
    "    if(pmu_data->last_charger_voltage >= charge_detection_threshold)\n"
    "    {\n"
    "        pmu_data->charger_on_auto_start_last_timestamp = now;\n"
    "        if(pcat_main_user_config_data_get()->charger_on_auto_start)\n"
    "            pmu_data->external_power_seen_in_ups_mode = TRUE;\n"
    "    }",
    "供电检测",
)
patch_once(
    "if((pmu_data->power_on_event==3 || pmu_data->power_on_event==4) &&\n"
    "               now > pmu_data->charger_on_auto_start_last_timestamp +",
    "if((pmu_data->power_on_event==3 || pmu_data->power_on_event==4 ||\n"
    "                pmu_data->external_power_seen_in_ups_mode) &&\n"
    "               now > pmu_data->charger_on_auto_start_last_timestamp +",
    "车载模式触发条件",
)
patch_once(
    "void pcat_pmu_manager_charger_on_auto_start(gboolean state)\n"
    "{\n"
    "    if(!g_pcat_pmu_manager_data.initialized)\n"
    "    {\n"
    "        return;\n"
    "    }\n\n"
    "    pcat_pmu_manager_charger_on_auto_start_internal(",
    "void pcat_pmu_manager_charger_on_auto_start(gboolean state)\n"
    "{\n"
    "    if(!g_pcat_pmu_manager_data.initialized)\n"
    "    {\n"
    "        return;\n"
    "    }\n\n"
    "    /* Re-arm monitoring whenever user switches UPS mode. No shutdown\n"
    "     * for a manually booted device that never saw external power. */\n"
    "    g_pcat_pmu_manager_data.external_power_seen_in_ups_mode = FALSE;\n"
    "    g_pcat_pmu_manager_data.charger_on_auto_start_last_timestamp =\n"
    "        g_get_monotonic_time();\n\n"
    "    pcat_pmu_manager_charger_on_auto_start_internal(",
    "模式切换重新计时",
)
path.write_text(s)
print("已修复车载 UPS 模式：保留原厂开机事件，另支持检测到外部供电后拔电倒计时")
