#!/bin/sh
# 扫描队列和 AT/子进程超时使用单调时钟，避免 NTP 回拨延长等待。
set -eu
. "$(dirname "$0")/../../scripts/lib/patch.sh"
feed=${1:?需要 QModem Feed 目录}
pc_init
pc_load "$feed/application/modem_scan/src/modem_scand.c"
pc_replace 'static int capture_exec(char *const argv[], char *out, size_t out_len, int timeout_sec)
{' '/* Elapsed waits must survive NTP corrections of the wall clock. */
static time_t monotonic_seconds(void)
{
	struct timespec ts;
	if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) {
		log_msg(LOG_L_ERR, "cannot read monotonic clock");
		abort();
	}
	return ts.tv_sec;
}

static int init_queue_condition(void)
{
	pthread_condattr_t attr;
	int rc = pthread_condattr_init(&attr);
	if (rc != 0)
		return rc;
	rc = pthread_condattr_setclock(&attr, CLOCK_MONOTONIC);
	if (rc == 0)
		rc = pthread_cond_init(&g.queue_cond, &attr);
	pthread_condattr_destroy(&attr);
	return rc;
}

static int capture_exec(char *const argv[], char *out, size_t out_len, int timeout_sec)
{' 'QModem 单调时钟辅助函数'
pc_replace '	pthread_cond_init(&g.queue_cond, NULL);' '	if (init_queue_condition() != 0) {
		log_msg(LOG_L_ERR, "cannot initialize monotonic scan queue condition");
		return 1;
	}' 'QModem 扫描条件变量初始化'
pc_awk '
function count(s,t, n,p) { n=0; while((p=index(s,t))) { n++; s=substr(s,p+length(t)) } return n }
BEGIN { RS="\0"; ORS=""; old="time(NULL)"; new="monotonic_seconds()" }
{
    if (count($0,old)==0 && count($0,new)==6) { print; next }
    if (count($0,old)!=6 || count($0,new)!=0) exit 1
    s=$0
    while((p=index(s,old))) { printf "%s%s",substr(s,1,p-1),new; s=substr(s,p+length(old)) }
    printf "%s",s
}'
pc_commit
echo 'QModem：扫描延时及 AT/子进程超时已改为单调时钟，保留官方扫描和拨号配置。'
