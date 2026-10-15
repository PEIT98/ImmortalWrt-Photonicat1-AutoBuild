#include "modem-manager.h"
/* PMU-only: QModem owns all 5G/LTE USB, dial-up, modem GPIO and RF-kill state. */
gboolean pcat_modem_manager_init(void) { return TRUE; }
void pcat_modem_manager_uninit(void) {}
gboolean pcat_modem_manager_status_get(PCatModemManagerMode *mode,
    PCatModemManagerSIMState *sim_state, gboolean *rfkill_state,
    gint *signal_strength, gchar **isp_name, gchar **isp_plmn)
{
    if (mode) *mode = PCAT_MODEM_MANAGER_MODE_NONE;
    if (sim_state) *sim_state = PCAT_MODEM_MANAGER_SIM_STATE_ABSENT;
    if (rfkill_state) *rfkill_state = FALSE;
    if (signal_strength) *signal_strength = 0;
    if (isp_name) *isp_name = NULL;
    if (isp_plmn) *isp_plmn = NULL;
    return FALSE;
}
PCatModemManagerDeviceType pcat_modem_manager_device_type_get(void) {
    return PCAT_MODEM_MANAGER_DEVICE_NONE;
}
void pcat_modem_manager_device_rfkill_mode_set(gboolean state) { (void)state; }
guint pcat_modem_manager_device_power_usage_get(void) { return 0; }
