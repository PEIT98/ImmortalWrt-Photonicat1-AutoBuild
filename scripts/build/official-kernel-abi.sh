#!/usr/bin/env bash
# 用官方发布的源码和内核配置构建；实际 ABI 不一致时禁止发布。
set -euo pipefail

fail() { echo "::error::$*" >&2; exit 1; }
mode=${1:?需要 pin、merge 或 verify}
src=${2:?需要 ImmortalWrt 源码目录}
metadata=${3:?需要官方元数据目录}
base=${PWRT_OFFICIAL_TARGET_URL:-https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/targets/rockchip/armv8}

case "$mode" in
  pin)
    mkdir -p "$metadata"
    for file in version.buildinfo config.buildinfo; do
      curl --fail --location --silent --show-error --retry 3 "$base/$file" -o "$metadata/$file"
      test -s "$metadata/$file" || fail "官方 $file 为空"
    done
    curl --fail --location --silent --show-error --retry 3 "$base/packages/" -o "$metadata/packages.html"
    version=$(cat "$metadata/version.buildinfo")
    [[ $version =~ ^r[0-9]+-([0-9a-f]{10})$ ]] || fail "无法识别官方版本：$version"
    revision=${BASH_REMATCH[1]}
    full_revision=$(curl --fail --location --silent --show-error --retry 3 \
      "https://api.github.com/repos/immortalwrt/immortalwrt/commits/$revision" | jq -r '.sha // empty')
    [[ $full_revision =~ ^[0-9a-f]{40}$ && $full_revision == "$revision"* ]] ||
      fail '无法将官方版本号解析为 ImmortalWrt 源码提交'
    mapfile -t kernels < <(grep -Eo 'kernel-[0-9][0-9.]*~[0-9a-f]{32}-r[0-9]+\.apk' "$metadata/packages.html" | sort -u)
    [ "${#kernels[@]}" -eq 1 ] || fail "官方软件包列表必须恰有一个 kernel 包"
    printf '%s\n' "${kernels[0]}" > "$metadata/kernel-package"
    grep -Fxq 'CONFIG_TARGET_DEVICE_rockchip_armv8_DEVICE_ariaboard_photonicat=y' "$metadata/config.buildinfo" ||
      fail '官方配置不包含光影猫一代目标'
    git -C "$src" fetch --depth=1 origin "$full_revision"
    git -C "$src" checkout --detach FETCH_HEAD
    [ "$(git -C "$src" rev-parse HEAD)" = "$full_revision" ] || fail '源码版本与官方发布记录不一致'
    echo "官方源码：$version；官方内核：${kernels[0]}"
    ;;
  merge)
    config=$src/.config
    official=$metadata/config.buildinfo
    test -s "$config" && test -s "$official" || fail '缺少参考配置或官方构建配置'
    tmp=$(mktemp "${config}.official-abi.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    # 其余硬件/插件选择仍取参考配置；内核构建开关以官方发布配置为准。
    awk '
      function kernel_key(k) {
        return k ~ /^CONFIG_KERNEL_/ || k == "CONFIG_ALL_KMODS" ||
          k == "CONFIG_ALL_NONSHARED" || k == "CONFIG_DWARVES" ||
          k == "CONFIG_REPRODUCIBLE_DEBUG_INFO"
      }
      function key_of(s, k) {
        k=s; sub(/^# /,"",k); sub(/(=| is not set).*$/, "", k); return k
      }
      FNR==NR {
        k=key_of($0)
        if (kernel_key(k) && $0 ~ /^(# )?CONFIG_/) official[k]=$0
        next
      }
      {
        k=key_of($0)
        if (kernel_key(k) && $0 ~ /^(# )?CONFIG_/) next
        print
      }
      END {
        print "# Official ImmortalWrt kernel configuration (config.buildinfo)"
        for (k in official) print official[k]
      }
    ' "$official" "$config" > "$tmp"
    test -s "$tmp" || fail '内核配置合并失败'
    mv "$tmp" "$config"
    trap - EXIT
    echo '已保留光影猫软件包，并以官方内核配置覆盖参考配置。'
    ;;
  verify)
    expected=$(cat "$metadata/kernel-package")
    [[ $expected =~ ^kernel-([0-9][0-9.]*)~([0-9a-f]{32})-r[0-9]+\.apk$ ]] || fail '官方内核包名称无效'
    version=${BASH_REMATCH[1]}
    abi=${BASH_REMATCH[2]}
    package_dir=$src/bin/targets/rockchip/armv8/packages
    mapfile -t built < <(find "$package_dir" -maxdepth 1 -type f -name 'kernel-*.apk' -printf '%f\n')
    [ "${#built[@]}" -eq 1 ] || fail '构建产物必须恰有一个 kernel 包'
    [ "${built[0]}" = "$expected" ] || fail "内核 ABI 与官方不一致：本机 ${built[0]}，官方 $expected"
    mapfile -t vermagic < <(find "$src/build_dir" -type f -name .vermagic -path '*/linux-rockchip_armv8/linux-*/*')
    [ "${#vermagic[@]}" -eq 1 ] || fail '找不到唯一的 Rockchip 内核 .vermagic'
    [ "$(cat "${vermagic[0]}")" = "$abi" ] || fail '实际内核 .vermagic 与官方 ABI 不一致'
    # SDK/软件源日后更新可能移除旧快照包；发布前确认官方 kmods 仍在对应目录。
    curl --fail --location --silent --show-error --retry 3 \
      "$base/kmods/$version-1-$abi/" -o "$metadata/kmods.html"
    grep -Eq 'kmod-usb-net-cdc-mbim-[^"<> ]+\.apk' "$metadata/kmods.html" ||
      fail '官方对应 ABI 的 USB MBIM 驱动包不存在'
    echo "通过：固件 kernel 包和 .vermagic 均为官方 ABI $version~$abi"
    ;;
  *) fail "未知模式：$mode" ;;
esac
