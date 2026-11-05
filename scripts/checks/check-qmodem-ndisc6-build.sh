#!/bin/bash
# 在固件编译前验证真实归档、musl 编译及所有 IPv6 程序安装。
set -euo pipefail
feed=${1:?需要 ndisc6 包目录}; downloads=${2:?需要下载目录}
value() {
    awk -v name="$1" 'index($0,name)==1 {s=substr($0,length(name)+1); if(s ~ /^[[:space:]]*:?=/) {sub(/^[[:space:]]*:?=[[:space:]]*/,"",s); sub(/[[:space:]]+$/,"",s); n++; result=s}} END {if(n!=1 || result=="")exit 1; print result}' "$feed/Makefile"
}
version=$(value PKG_VERSION); expected=$(value PKG_HASH); flags=$(value 'TARGET_CFLAGS +')
[[ $version =~ ^[0-9]+(\.[0-9]+)*$ && $expected =~ ^[0-9a-f]{64}$ ]]
archive=$(realpath "$downloads/ndisc6-$version.tar.bz2")
[[ $(sha256sum "$archive" | cut -d ' ' -f1) == "$expected" ]]
compiler=$(command -v musl-gcc)
machine=$(gcc -dumpmachine)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
# Reject links and paths escaping the disposable extraction tree.
tar -tjf "$archive" > "$tmp/list"
tar -tvjf "$archive" > "$tmp/members"
if grep -Eq '(^/|(^|/)\.\.(/|$))' "$tmp/list" || grep -Eq '^[lh]' "$tmp/members"; then
    echo '::error::不安全的 ndisc6 归档成员' >&2; exit 1
fi
tar -xjf "$archive" --no-same-owner --no-same-permissions -C "$tmp"
[[ -f $tmp/ndisc6-$version/configure ]]
mkdir "$tmp/build"
cd "$tmp/build"
"$tmp/ndisc6-$version/configure" --disable-nls --prefix=/usr "CC=$compiler" LDFLAGS=-static "CFLAGS=-O2 $flags -idirafter /usr/include -idirafter /usr/include/$machine" >configure.log 2>&1 || { tail -c 8000 configure.log; exit 1; }
make -j2 >build.log 2>&1 || { tail -c 8000 build.log; exit 1; }
make install "DESTDIR=$tmp/install" >install.log 2>&1 || { tail -c 8000 install.log; exit 1; }
for program in usr/bin/ndisc6 usr/bin/rdisc6 usr/bin/rltraceroute6 usr/bin/tcptraceroute6 usr/bin/tracert6 usr/sbin/rdnssd; do [[ -f $tmp/install/$program ]]; done
printf 'ndisc6 %s：SHA256、musl 编译及 6 个程序安装检查通过。\n' "$version"
