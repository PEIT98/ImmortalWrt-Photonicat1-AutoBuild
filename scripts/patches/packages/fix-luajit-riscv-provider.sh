#!/bin/sh
# ImmortalWrt 25.12 的 luajit 在 2026-11-04 新增 @!riscv64。
# luajit2 同时提供 luajit 虚拟包，元数据生成器会把该限制传播成
# PACKAGE_luajit2<PACKAGE_当前包 的自依赖，导致 make defconfig 失败。
# 本固件仅构建 aarch64；在此目标上该限制恒为真，移除它不改变选包结果。
set -eu

src=${1:?需要 ImmortalWrt 源码目录}
config="$src/.config"
luajit="$src/feeds/packages/lang/lua/luajit/Makefile"
luajit2="$src/feeds/packages/lang/lua/luajit2/Makefile"

test -f "$config" && test -f "$luajit" && test -f "$luajit2" || {
    echo '::error::LuaJIT 兼容修复缺少目标配置或 Packages Feed' >&2
    exit 1
}
grep -Fxq 'CONFIG_TARGET_rockchip_armv8=y' "$config" &&
grep -Fxq 'CONFIG_ARCH="aarch64"' "$config" || {
    echo '::error::LuaJIT 兼容修复仅适用于光影猫 armv8/aarch64 目标' >&2
    exit 1
}
grep -Fxq 'PKG_NAME:=luajit' "$luajit" &&
grep -Eq '^[[:space:]]*PROVIDES:=luajit[[:space:]]*$' "$luajit2" || {
    echo '::error::LuaJIT 包或 luajit2 虚拟提供关系已变化' >&2
    exit 1
}

old='  DEPENDS:=@HAS_LUAJIT_ARCH @!riscv64'
new='  DEPENDS:=@HAS_LUAJIT_ARCH'
if grep -Fxq "$old" "$luajit"; then
    test "$(grep -Fxc "$old" "$luajit")" -eq 1 || exit 1
    sed -i 's/^  DEPENDS:=@HAS_LUAJIT_ARCH @!riscv64$/  DEPENDS:=@HAS_LUAJIT_ARCH/' "$luajit"
    grep -Fxq "$new" "$luajit" || exit 1
    echo '已移除 aarch64 上无效的 LuaJIT RISC-V 限制，避免虚拟包 Kconfig 自依赖。'
elif grep -Eq '^[[:space:]]*DEPENDS:=@HAS_LUAJIT_ARCH[[:space:]]*$' "$luajit"; then
    echo 'LuaJIT 上游尚无触发自依赖的 RISC-V 限制，无需修改。'
else
    echo '::error::LuaJIT 依赖格式变化，请检查上游后再适配' >&2
    exit 1
fi
