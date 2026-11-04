#!/bin/sh
# 应用独立插件配置；只关闭参考配置中残留的 PassWall 子选项。
set -eu
. "$(dirname "$0")/../lib/patch.sh"
pc_init
pc_load "${1:?需要 .config 路径}"
overrides=$(cd "$(dirname "$0")/../.." && pwd)/photonicat1.config
[ -f "$overrides" ] || pc_fail "Missing package override file: $overrides"
awk -v removed_file="$PC_TMP/removed" -v selected_file="$PC_TMP/selected" '
FILENAME==ARGV[1] {
 line=$0; sub(/^[[:space:]]+/,"",line); sub(/[[:space:]]+$/,"",line)
 if(line=="" || (line ~ /^#/ && line !~ /^# CONFIG_/)) next
 if(line !~ /^CONFIG_[A-Za-z0-9_+.-]+=(y|m|n|".*")$/ && line !~ /^# CONFIG_[A-Za-z0-9_+.-]+ is not set$/) {
   print FILENAME ":" FNR ": invalid config entry: " line > "/dev/stderr"; bad=1; next
 }
 key=line; sub(/^# /,"",key); sub(/(=| is not set).*$/,"",key)
 if(key in overrides) { print "duplicate config key: " key > "/dev/stderr"; bad=1 }
 overrides[key]=line; next
}
{
 key=$0; sub(/^# /,"",key)
 if(key ~ /^CONFIG_[A-Za-z0-9_+.-]+(=| is not set)/) {
   sub(/(=| is not set).*$/,"",key)
   if(key in overrides) next
   if(index(key,"CONFIG_PACKAGE_luci-app-passwall_INCLUDE_")==1) { removed[key]=1; next }
 }
 print
}
END {
 if(bad) exit 1
 print "\n# Photonicat1 configuration overrides (photonicat1.config)"
 for(key in removed) print "# " key " is not set" > removed_file
 for(key in overrides) print key "\t" overrides[key] > selected_file
}' "$overrides" "$PC_WORK" > "$PC_TMP/base" || pc_fail '独立配置校验失败'
cat "$PC_TMP/base" > "$PC_WORK"
if [ -f "$PC_TMP/removed" ]; then LC_ALL=C sort "$PC_TMP/removed" >> "$PC_WORK"; fi
if [ -f "$PC_TMP/selected" ]; then LC_ALL=C sort "$PC_TMP/selected" | cut -f2- >> "$PC_WORK"; fi
pc_commit
echo 'Photonicat1 插件覆盖项已应用，其他配置保留。'
