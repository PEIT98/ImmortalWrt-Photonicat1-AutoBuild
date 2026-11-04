
static void check_case(const char *driver, const char *port, int expected_nets) {
    struct scan_result result = {0};
    interfaces[4].driver = driver;
    interfaces[4].port = port;
    scan_usb_slot("6-1", &result);
    require(result.net_devices.len == (size_t)expected_nets,
            "网卡被 AT 白名单过滤，或错误接纳了未知驱动");
    require(sl_contains(&result.at_ports, "/dev/ttyUSB2"), "白名单内 AT 口丢失");
    require(sl_contains(&result.at_ports, "/dev/ttyUSB3"), "第二个 AT 口丢失");
    require(sl_contains(&result.at_ports, "/dev/ttyUSB0") == !has_rule,
            "诊断串口的白名单行为改变");
    require(sl_contains(&result.at_ports, "/dev/ttyUSB1") == !has_rule,
            "语音端口被错误加入 AT 口");
    if (has_rule)
        require(!strcmp(result.voice_pcm_port, "/dev/ttyUSB1"), "语音端口保留失效");
    sl_free(&result.net_devices);
    sl_free(&result.at_ports);
}
int main(void) {
    check_case("cdc_ether", "1.10", 1);
    check_case("rndis_host", "1.11", 1);
    check_case("cdc_mbim", "1.8", 1);
    check_case("cdc_ncm", "1.6", 1);
    check_case("huawei_cdc_ncm", "1.7", 1);
    check_case("qmi_wwan", "1.4", 1);
    check_case("qmi_wwan_q", "1.9", 1);
    check_case("usb-storage", "1.10", 0);
    has_rule = 0;
    check_case("cdc_ether", "1.10", 1);
    has_rule = 1;
    check_case("cdc_ether", "1.200", 1);
    net_first = 1;
    check_case("cdc_ether", "1.10", 1);
    strict_rule = 1;
    struct scan_result result = {0};
    scan_usb_slot("6-1", &result);
    require(sl_contains(&result.net_devices, "usb0"), "AT 全部被限制时网卡仍应被收集");
    require(result.at_ports.len == 0, "严格 AT 白名单被放宽");
    require(!strcmp(result.voice_pcm_port, "/dev/ttyUSB1"), "严格白名单下语音端口丢失");
    sl_free(&result.net_devices);
    sl_free(&result.at_ports);
    puts("12 组 USB 扫描回归通过：通用网卡识别、接口顺序、严格 AT 过滤和语音端口。");
    return 0;
}
