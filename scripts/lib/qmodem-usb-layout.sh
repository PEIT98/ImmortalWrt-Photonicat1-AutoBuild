#!/bin/sh
# Literal C source in environment variables; never evaluated as shell arguments.
# shellcheck disable=SC2089,SC2090
# Literal upstream anchors shared with the compiled scanner regression.
START='static void scan_usb_slot('
export START
END='
static void scan_associated_usb('
export END
GUARD='		if (!interface_allowed(&rule, if_port)) {
			log_msg(LOG_L_DEBUG, "skip usb %s interface %s by modem_port_rule", slot, if_port);
			continue;
		}
'
export GUARD
SERIAL='		if (!strcmp(driver, "option") || !strcmp(driver, "cdc_acm") ||
		    !strcmp(driver, "qcserial") || !strcmp(driver, "usbserial_generic") ||
		    !strcmp(driver, "usbserial")) {
'
export SERIAL
ORIGINAL='		if (!interface_allowed(&rule, if_port)) {
			log_msg(LOG_L_DEBUG, "skip usb %s interface %s by modem_port_rule", slot, if_port);
			continue;
		}
		if (!strcmp(driver, "option") || !strcmp(driver, "cdc_acm") ||
		    !strcmp(driver, "qcserial") || !strcmp(driver, "usbserial_generic") ||
		    !strcmp(driver, "usbserial")) {
'
export ORIGINAL
LEGACY_PATCHED='		if (!strcmp(driver, "option") || !strcmp(driver, "cdc_acm") ||
		    !strcmp(driver, "qcserial") || !strcmp(driver, "usbserial_generic") ||
		    !strcmp(driver, "usbserial")) {
			/* photonicat-usb-net-scan: 白名单只筛选 AT 串口。 */
			if (!interface_allowed(&rule, if_port)) {
				log_msg(LOG_L_DEBUG, "skip usb %s interface %s by modem_port_rule", slot, if_port);
				continue;
			}
'
export LEGACY_PATCHED
NETWORK_CONDITION='!strncmp(driver, "qmi_wwan", 8) || !strcmp(driver, "cdc_mbim") ||
			   strstr(driver, "cdc_ncm") || !strcmp(driver, "cdc_ether") ||
			   !strcmp(driver, "rndis_host")'
export NETWORK_CONDITION
NETWORK_BODY='			char net_path[512];
			snprintf(net_path, sizeof(net_path), "%s/net", path);
			list_net_devices(net_path, &res->net_devices);
'
export NETWORK_BODY
NETWORK_TAIL='		} else if (!strncmp(driver, "qmi_wwan", 8) || !strcmp(driver, "cdc_mbim") ||
			   strstr(driver, "cdc_ncm") || !strcmp(driver, "cdc_ether") ||
			   !strcmp(driver, "rndis_host")) {
			char net_path[512];
			snprintf(net_path, sizeof(net_path), "%s/net", path);
			list_net_devices(net_path, &res->net_devices);
		}
'
export NETWORK_TAIL
NETWORK_FIRST='		/* photonicat-usb-net-first: 先收集网卡，再筛选 AT 串口。 */
		if (!strncmp(driver, "qmi_wwan", 8) || !strcmp(driver, "cdc_mbim") ||
			   strstr(driver, "cdc_ncm") || !strcmp(driver, "cdc_ether") ||
			   !strcmp(driver, "rndis_host")) {
			char net_path[512];
			snprintf(net_path, sizeof(net_path), "%s/net", path);
			list_net_devices(net_path, &res->net_devices);
			continue;
		}
'
export NETWORK_FIRST
PATH_LINE='		snprintf(path, sizeof(path), "%s/%s", slot_path, de->d_name);
'
export PATH_LINE
SERIAL_END='			sl_free(&ttys);
		}
'
export SERIAL_END
