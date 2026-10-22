#!/usr/bin/env python3
"""编译并执行上游 USB 扫描函数，回归网卡识别、AT 过滤和语音端口。"""

import argparse
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "usb_net_patch", ROOT / "scripts/patches/fix-qmodem-usb-net-filter.py"
)
patch = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patch)

# 只替换 sysfs 读写和规则加载；下方执行的是 Feed 中真实的扫描函数。
HARNESS = r'''
#include <dirent.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct str_list { char *items[32]; size_t len; };
struct port_rule {
    int has_rule, option_driver;
    struct str_list include;
    char voice_pcm_interface[32];
};
struct scan_result {
    struct str_list net_devices, at_ports;
    char modem_path[256], vid[16], pid[16];
    char voice_pcm_port[160], voice_pcm_interface[32];
    int option_driver;
};
struct usb_interface { const char *port, *driver, *tty, *net; };
static struct usb_interface interfaces[] = {
    {"1.0", "option", "ttyUSB0", NULL},
    {"1.1", "option", "ttyUSB1", NULL},
    {"1.2", "option", "ttyUSB2", NULL},
    {"1.3", "option", "ttyUSB3", NULL},
    {"1.10", "cdc_ether", NULL, "usb0"}
};
static size_t cursor;
static int has_rule = 1;
static int net_first;
static int strict_rule;
enum { LOG_L_DEBUG, LOG_L_WARN };
static void log_msg(int level, const char *format, ...) {
    (void)level; (void)format;
}
static void require(int condition, const char *message) {
    if (!condition) { fprintf(stderr, "%s\n", message); exit(1); }
}
static void sl_init(struct str_list *list) { memset(list, 0, sizeof(*list)); }
static void sl_add(struct str_list *list, const char *item) {
    require(list->len < 32, "测试列表溢出");
    list->items[list->len++] = strdup(item);
}
static int sl_contains(const struct str_list *list, const char *item) {
    for (size_t i = 0; i < list->len; i++)
        if (!strcmp(list->items[i], item)) return 1;
    return 0;
}
static void sl_free(struct str_list *list) {
    for (size_t i = 0; i < list->len; i++) free(list->items[i]);
    sl_init(list);
}
static struct usb_interface *lookup(const char *path) {
    const char *port = strchr(path, ':');
    if (!port) return NULL;
    port++;
    for (size_t i = 0; i < sizeof(interfaces) / sizeof(interfaces[0]); i++) {
        size_t n = strlen(interfaces[i].port);
        if (!strncmp(port, interfaces[i].port, n) &&
            (port[n] == '/' || port[n] == '\0')) return &interfaces[i];
    }
    return NULL;
}
static DIR *fake_opendir(const char *path) {
    (void)path; cursor = 0; return (DIR *)&cursor;
}
static struct dirent *fake_readdir(DIR *dir) {
    static struct dirent entry;
    (void)dir;
    if (cursor == sizeof(interfaces) / sizeof(interfaces[0])) return NULL;
    size_t index = cursor++;
    if (net_first)
        index = (index + 4) % 5;
    snprintf(entry.d_name, sizeof(entry.d_name), "6-1:%s", interfaces[index].port);
    return &entry;
}
static int fake_closedir(DIR *dir) { (void)dir; return 0; }
static int is_dir(const char *path) { (void)path; return 1; }
static int path_exists(const char *path) { (void)path; return 1; }
static void read_file_trim(const char *path, char *out, size_t len) {
    snprintf(out, len, "%s", strstr(path, "idVendor") ? "2c7c" : "0801");
}
static void load_port_rule(const char *vid, const char *pid, struct port_rule *rule) {
    (void)vid; (void)pid;
    memset(rule, 0, sizeof(*rule));
    if (!has_rule) return;
    rule->has_rule = 1;
    if (strict_rule) {
        sl_add(&rule->include, "9.9");
    } else {
        sl_add(&rule->include, "1.2");
        sl_add(&rule->include, "1.3");
        sl_add(&rule->include, "1.4");
    }
    snprintf(rule->voice_pcm_interface, sizeof(rule->voice_pcm_interface), "1.1");
}
static void apply_option_driver(const char *vid, const char *pid) {
    (void)vid; (void)pid;
}
static int readlink_basename(const char *path, char *out, size_t len) {
    struct usb_interface *entry = lookup(path);
    if (!entry) return -1;
    snprintf(out, len, "%s", entry->driver);
    return 0;
}
static void list_child_matching(const char *path, const char *prefix, struct str_list *out) {
    struct usb_interface *entry = lookup(path);
    if (entry && entry->tty && !strncmp(entry->tty, prefix, strlen(prefix)))
        sl_add(out, entry->tty);
}
static void list_net_devices(const char *path, struct str_list *out) {
    struct usb_interface *entry = lookup(path);
    if (entry && entry->net) sl_add(out, entry->net);
}
#define opendir fake_opendir
#define readdir fake_readdir
#define closedir fake_closedir
'''

CASES = r'''
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
'''


def build_and_run(source: str, directory: Path, name: str, compiler: str):
    start = source.index("static int interface_allowed(")
    end = source.index("\nstatic void apply_option_driver(", start)
    unit = HARNESS + source[start:end] + patch.usb_scan_function(source) + CASES
    c_file = directory / f"{name}.c"
    executable = directory / name
    c_file.write_text(unit, encoding="utf-8")
    subprocess.run(
        # 上游固定长度 sysfs 缓冲区会触发主机 GCC 的既有截断提示；测试路径均很短。
        [compiler, "-std=c99", "-D_GNU_SOURCE", "-Wall", "-Wextra", "-Werror",
         "-Wno-format-truncation",
         str(c_file), "-o", str(executable)], check=True,
    )
    return subprocess.run([str(executable)], text=True, capture_output=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("feed", type=Path, help="已应用补丁的 QModem Feed 目录")
    args = parser.parse_args()
    source = (args.feed / patch.SCANNER).read_text(encoding="utf-8")
    if patch.NETWORK_FIRST not in source or patch.patch_source(source) != source:
        parser.exit(1, "USB 网卡扫描补丁未生效，或重复执行改变源码\n")
    body = patch.usb_scan_function(source)
    if body.count(patch.SERIAL_END) != 1:
        parser.exit(1, "AT 串口分支结构变化\n")
    original_body = body.replace(patch.NETWORK_FIRST, "", 1).replace(
        patch.SERIAL_END, "\t\t\tsl_free(&ttys);\n" + patch.NETWORK_TAIL, 1
    )
    original = source.replace(body, original_body, 1)
    if patch.patch_source(original) != source:
        parser.exit(1, "补丁修改超出预期范围\n")
    legacy = original.replace(patch.ORIGINAL, patch.LEGACY_PATCHED, 1)
    if patch.patch_source(legacy) != source:
        parser.exit(1, "上一版补丁迁移失败\n")
    try:
        patch.patch_source(original.replace(patch.GUARD, "", 1))
    except ValueError:
        pass
    else:
        parser.exit(1, "上游结构变化时没有停止修改\n")
    compiler = shutil.which("cc")
    if not compiler:
        parser.exit(1, "缺少主机 C 编译器，请安装 build-essential\n")
    with tempfile.TemporaryDirectory(prefix="qmodem-usb-test-") as tmp:
        directory = Path(tmp)
        before = build_and_run(original, directory, "before", compiler)
        if before.returncode != 1 or "网卡被 AT 白名单过滤" not in before.stderr:
            parser.exit(1, "未能复现原版 ECM 接口过滤问题\n")
        after = build_and_run(source, directory, "after", compiler)
        if after.returncode:
            parser.exit(1, after.stderr)
        print(after.stdout, end="")
    print("原版故障复现、旧补丁迁移、重复执行及上游结构检查通过。")


if __name__ == "__main__":
    main()
