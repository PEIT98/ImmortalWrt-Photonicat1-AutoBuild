#!/bin/sh
# 构建主机脚本：先校验，再提交全部文本修改。
set -eu
. "$(dirname "$0")/../lib/patch.sh"
. "$(dirname "$0")/../lib/qmodem-usb-layout.sh"
pc_init
pc_load "${1:?需要 QModem Feed 目录}/application/modem_scan/src/modem_scand.c"
pc_awk '
function count(s,t, n,p) { n=0; while(length(t) && (p=index(s,t))) { n++; s=substr(s,p+length(t)) } return n }
function repl(s,a,b, p) { p=index(s,a); if(!p) return s; return substr(s,1,p-1) b substr(s,p+length(a)) }
function fail(msg) { print msg > "/dev/stderr"; exit 1 }
BEGIN {
 RS="\0"; ORS=""
 start=ENVIRON["START"]; end=ENVIRON["END"]; guard=ENVIRON["GUARD"]; serial=ENVIRON["SERIAL"]
 original=ENVIRON["ORIGINAL"]; legacy=ENVIRON["LEGACY_PATCHED"]; tail=ENVIRON["NETWORK_TAIL"]
 first=ENVIRON["NETWORK_FIRST"]; path=ENVIRON["PATH_LINE"]
}
{
 if(count($0,start)!=1 || count($0,end)!=1) fail("QModem USB 扫描函数布局变化")
 a=index($0,start); z=index($0,end); if(z<=a) fail("QModem USB 扫描函数顺序变化")
 before=substr($0,a,z-a); body=before
 if(count(body,legacy)==1) body=repl(body,legacy,original)
 if(index(body,"photonicat-usb-net-first")) {
   if(count(body,path first)!=1 || count(body,original)!=1 || index(body,tail) || index(body,first)>=index(body,guard))
     fail("QModem 网卡前置补丁结构不完整")
   print $0; next
 }
 # Upstream independently collects network interfaces and filters only AT ports.
 atguard="if (!interface_allowed(&rule, if_port)) {"
 if(count(body,path)==1 && count(body,serial)==1 && count(body,tail)==1 && count(body,atguard)==1 && index(body,serial)<index(body,tail)) {
   at=substr(body,index(body,serial),index(body,tail)-index(body,serial))
   if(index(at,"sl_init(&ttys);") && index(at,atguard)<index(at,"sl_init(&ttys);")) {
     check=substr(at,index(at,atguard),index(at,"sl_init(&ttys);")-index(at,atguard))
     if(index(check,"continue;")) { print $0; next }
   }
 }
 if(count(body,original)!=1 || count(body,tail)!=1 || count(body,path)!=1 || index(body,"photonicat-usb-net-scan"))
   fail("QModem 端口过滤逻辑变化，停止修改以保留上游功能")
 body=repl(body,tail,"\t\t}\n"); body=repl(body,path,path first)
 print substr($0,1,a-1) body substr($0,z)
}'
pc_commit
echo 'QModem：保留通用 USB 网卡识别、AT 白名单和语音端口规则。'
