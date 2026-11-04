/* Exercise the actual patched CM source with only device IO intercepted. */
#include <assert.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <fcntl.h>
#include <unistd.h>

static char host_mode;
static int opens, reads, writes, commands, link_up, missing, write_failure;
static int read_failure, verification_failure;
static int fake_open(const char *path, int flags, ...) {
    (void)flags;
    assert(!strcmp(path, "/sys/class/net/cell42/qmi/raw_ip"));
    opens++;
    if (missing) { errno = ENOENT; return -1; }
    return 77;
}
static ssize_t fake_read(int fd, void *buf, size_t count) {
    assert(fd == 77 && count == 1);
    reads++;
    if (read_failure) return -1;
    *(char *)buf = verification_failure && writes ? 'N' : host_mode;
    return 1;
}
static ssize_t fake_write(int fd, const void *buf, size_t count) {
    assert(fd == 77 && count == 1);
    writes++;
    if (write_failure) { errno = EBUSY; return -1; }
    host_mode = *(const char *)buf;
    return 1;
}
static off_t fake_lseek(int fd, off_t offset, int whence) {
    assert(fd == 77 && offset == 0 && whence == SEEK_SET);
    return 0;
}
static int fake_close(int fd) { (void)fd; return 0; }
static int fake_system(const char *cmd) {
    commands++;
    assert(strstr(cmd, "ip link set dev cell42") || strstr(cmd, "ifconfig cell42"));
    if (strstr(cmd, "down")) link_up = 0;
    else if (strstr(cmd, "up")) link_up = 1;
    else assert(0);
    return 0;
}
static int fake_socket(int domain, int type, int protocol) {
    (void)domain; (void)type; (void)protocol; return 88;
}
static int fake_ioctl(int fd, unsigned long request, ...) {
    va_list args;
    assert(fd == 88 && request == SIOCGIFFLAGS);
    va_start(args, request);
    struct ifreq *ifr = va_arg(args, struct ifreq *);
    ifr->ifr_flags = link_up ? IFF_UP : 0;
    va_end(args);
    return 0;
}
#define open fake_open
#define read fake_read
#define write fake_write
#define lseek fake_lseek
#define close fake_close
#define system fake_system
#define socket fake_socket
#define ioctl fake_ioctl
#include QMODEM_CM_SOURCE
#undef open
#undef read
#undef write
#undef lseek
#undef close
#undef system
#undef socket
#undef ioctl

FILE *logfilefp;
const struct request_ops qmi_request_ops = {0}, mbim_request_ops = {0}, atc_request_ops = {0};
const char *get_time(void) { return "test"; }
void no_trunc_strncpy(char *dst, const char *src, size_t n) { snprintf(dst, n, "%s", src); }

static PROFILE_T profile(void) {
    PROFILE_T p = {0};
    p.managed_ipv4 = 1;
    p.qmi_data_format_valid = 1;
    p.request_ops = &qmi_request_ops;
    p.rawIP = 1;
    p.ipv4.Address = 0x0a010203;
    return p;
}
static void reset(void) {
    host_mode = 'N'; opens = reads = writes = commands = missing = write_failure = 0;
    read_failure = verification_failure = 0; link_up = 1;
}
int main(void) {
    PROFILE_T p = profile();
    reset();
    assert(photonicat_sync_qmi_format(&p, "cell42") == 0);
    assert(host_mode == 'Y' && writes == 1 && commands == 2 && link_up);
    /* No address comparison: an old/manual IP must not skip synchronization. */
    reset(); host_mode = 'Y';
    assert(photonicat_sync_qmi_format(&p, "cell42") == 0 && writes == 0 && commands == 0);
    reset(); host_mode = 'Y'; p.rawIP = 0;
    assert(photonicat_sync_qmi_format(&p, "cell42") == 0 && host_mode == 'N');
    reset(); p = profile(); link_up = 0;
    assert(photonicat_sync_qmi_format(&p, "cell42") == 0 && !link_up && commands == 0);
    reset(); p = profile(); missing = 1;
    assert(photonicat_sync_qmi_format(&p, "cell42") == 0 && writes == 0);
    reset(); p = profile(); write_failure = 1;
    assert(photonicat_sync_qmi_format(&p, "cell42") == -1 && link_up && commands == 2);
    reset(); p = profile(); read_failure = 1;
    assert(photonicat_sync_qmi_format(&p, "cell42") == -1 && commands == 0);
    reset(); p = profile(); verification_failure = 1;
    assert(photonicat_sync_qmi_format(&p, "cell42") == -1 && link_up);
    for (int i = 0; i < 6; i++) {
        reset(); p = profile();
        switch (i) {
            case 0: p.managed_ipv4 = 0; break;
            case 1: p.qmi_data_format_valid = 0; break;
            case 2: p.request_ops = &mbim_request_ops; break;
            case 3: p.qmap_mode = 1; break;
            case 4: strcpy(p.qmapnet_adapter, "cell42_1"); break;
            case 5: p.generic_mhi = 1; break;
        }
        assert(photonicat_sync_qmi_format(&p, "cell42") == 0 && opens == 0);
    }
    puts("PASS: negotiated raw-IP/Ethernet sync, stale addresses, link restoration, IO failures and excluded paths");
    return 0;
}
