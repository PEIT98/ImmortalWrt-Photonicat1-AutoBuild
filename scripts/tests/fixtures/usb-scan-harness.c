
#include <dirent.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define QMODEM_SYSFS_ROOT "/sys"

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
