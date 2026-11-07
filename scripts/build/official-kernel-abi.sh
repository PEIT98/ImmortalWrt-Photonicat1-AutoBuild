#!/usr/bin/env bash
# 用官方发布的源码和内核配置构建；实际 ABI 不一致时禁止发布。
set -euo pipefail

fail() { echo "::error::$*" >&2; exit 1; }
mode=${1:?需要 pin、merge、check-config、feed 或 verify}
src=${2:?需要 ImmortalWrt 源码目录}
metadata=${3:?需要官方元数据目录}
base=${PWRT_OFFICIAL_TARGET_URL:-https://downloads.immortalwrt.org/releases/25.12-SNAPSHOT/targets/rockchip/armv8}

expected_kernel() {
  expected=$(cat "$metadata/kernel-package")
  [[ $expected =~ ^kernel-([0-9][0-9.]*)~([0-9a-f]{32})-r[0-9]+\.apk$ ]] || fail '官方内核包名称无效'
  version=${BASH_REMATCH[1]}
  abi=${BASH_REMATCH[2]}
}

# 只替换内核配置生成的两个输入；固件安装包仍由项目 .config 选择。
bind_kernel_recipe() (
  . "$(dirname "$0")/../lib/patch.sh"
  pc_init
  pc_load "$src/include/kernel-defaults.mk"
  pc_replace '$(TOPDIR)/.config >> $(LINUX_DIR)/.config.target' \
    '$(TOPDIR)/.config.official-kernel >> $(LINUX_DIR)/.config.target' '内核构建开关输入'
  pc_replace 'kconfig $(TMP_DIR)/.packageinfo $(TOPDIR)/.config $(KERNEL_PATCHVER)' \
    'kconfig $(TMP_DIR)/.packageinfo $(TOPDIR)/.config.official-kernel $(KERNEL_PATCHVER)' '内核模块选包输入'
  pc_commit
)

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
    # config.buildinfo 是精简配置，缺少展开后的模块选择。ImageBuilder 保存
    # 官方完整 .config；先核对归档 SHA256，再仅提取该文件。
    imagebuilder=immortalwrt-imagebuilder-25.12-SNAPSHOT-rockchip-armv8.Linux-x86_64.tar.zst
    archive=$metadata/$imagebuilder
    config_tmp=$(mktemp "$metadata/.official-config.XXXXXX")
    trap 'rm -f "$archive" "$config_tmp"' EXIT
    curl --fail --location --silent --show-error --retry 3 "$base/sha256sums" -o "$metadata/sha256sums"
    mapfile -t sums < <(awk -v name="$imagebuilder" \
      '{file=$2; sub(/^\*/, "", file); sub(/^\.\//, "", file); if (file==name) print $1}' "$metadata/sha256sums")
    [ "${#sums[@]}" -eq 1 ] && [[ ${sums[0]} =~ ^[0-9a-f]{64}$ ]] || fail '找不到唯一的官方 ImageBuilder SHA256'
    curl --fail --location --silent --show-error --retry 3 "$base/$imagebuilder" -o "$archive"
    actual=$(sha256sum "$archive"); actual=${actual%% *}
    [ "$actual" = "${sums[0]}" ] || fail '官方 ImageBuilder SHA256 不符'
    tar --zstd -xOf "$archive" "${imagebuilder%.tar.zst}/.config" > "$config_tmp"
    grep -Fxq 'CONFIG_TARGET_rockchip_armv8=y' "$config_tmp" &&
      grep -Fxq 'CONFIG_ALL_KMODS=y' "$config_tmp" || fail '官方完整配置的目标或内核模块开关无效'
    mv "$config_tmp" "$metadata/official.config"
    rm -f "$archive"
    trap - EXIT
    git -C "$src" fetch --depth=1 origin "$full_revision"
    git -C "$src" checkout --detach FETCH_HEAD
    [ "$(git -C "$src" rev-parse HEAD)" = "$full_revision" ] || fail '源码版本与官方发布记录不一致'
    echo "官方源码：$version；官方内核：${kernels[0]}"
    ;;
  merge)
    config=$src/.config
    official=$metadata/official.config
    test -s "$config" && test -s "$official" || fail '缺少参考配置或官方构建配置'
    tmp=$(mktemp "${config}.official-abi.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    # 其余硬件/插件选择仍取参考配置；内核构建开关以官方发布配置为准。
    # 完整官方配置另存为内核专用输入，避免参考配置的显式 kmod 禁用项和
    # Docker 等用户态选包反向改变内核 ABI；ALL_NONSHARED 沿用参考配置。
    awk '
      function kernel_key(k) {
        return k ~ /^CONFIG_KERNEL_/ || k == "CONFIG_ALL_KMODS" ||
          k == "CONFIG_DWARVES" ||
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
        print "# Official ImmortalWrt kernel configuration (ImageBuilder full config)"
        for (k in official) print official[k]
      }
    ' "$official" "$config" > "$tmp"
    test -s "$tmp" || fail '内核配置合并失败'
    bind_kernel_recipe
    cp "$official" "$src/.config.official-kernel"
    mv "$tmp" "$config"
    trap - EXIT
    echo '已保留光影猫软件包，并以官方内核配置覆盖参考配置。'
    ;;
  check-config)
    expected_kernel
    official=$src/.config.official-kernel
    cmp -s "$official" "$metadata/official.config" || fail '内核专用配置与本次官方配置不一致'
    test -s "$src/tmp/.packageinfo" || fail '缺少当前软件包元数据，须在 feeds 和 defconfig 后预检'
    grep -Fq '$(TOPDIR)/.config.official-kernel >> $(LINUX_DIR)/.config.target' "$src/include/kernel-defaults.mk" &&
      grep -Fq 'kconfig $(TMP_DIR)/.packageinfo $(TOPDIR)/.config.official-kernel $(KERNEL_PATCHVER)' "$src/include/kernel-defaults.mk" ||
      fail '内核构建尚未绑定官方完整配置'
    patchver=$(sed -nE 's/^[[:space:]]*KERNEL_PATCHVER[[:space:]]*:=[[:space:]]*([0-9]+\.[0-9]+)[[:space:]]*$/\1/p' "$src/target/linux/rockchip/Makefile")
    [[ $patchver =~ ^[0-9]+\.[0-9]+$ && $version == "$patchver".* ]] || fail 'Rockchip 内核版本与官方包不一致'
    checks=$metadata/preflight
    mkdir -p "$checks"
    configs=()
    for platform in generic rockchip rockchip/armv8; do
      for file in "$src/target/linux/$platform/config-$patchver" "$src/target/linux/$platform/config-default"; do
        if [ -f "$file" ]; then configs+=("$file"); break; fi
      done
    done
    [ -f "$src/env/kernel-config" ] && configs+=("$src/env/kernel-config")
    [ "${#configs[@]}" -ge 2 ] || fail '缺少 Rockchip 内核基础配置'
    operators=()
    for ((i=1; i<${#configs[@]}; i++)); do operators+=(+); done
    # 与锁定源码 include/kernel-defaults.mk 的 Kernel/Configure/Default 相同；
    # 不编译内核，不写入构建目录的 .vermagic。
    perl "$src/scripts/kconfig.pl" "${operators[@]}" "${configs[@]}" > "$checks/.config.target"
    awk '/^(#[[:space:]]+)?CONFIG_KERNEL/{sub("CONFIG_KERNEL_","CONFIG_");print}' "$official" >> "$checks/.config.target"
    printf '%s\n' '# CONFIG_KALLSYMS_EXTRA_PASS is not set' '# CONFIG_KALLSYMS_ALL is not set' \
      'CONFIG_KALLSYMS_UNCOMPRESSED=y' >> "$checks/.config.target"
    perl "$src/scripts/package-metadata.pl" kconfig "$src/tmp/.packageinfo" "$official" "$patchver" > "$checks/.config.override"
    perl "$src/scripts/kconfig.pl" 'm+' '+' "$checks/.config.target" /dev/null "$checks/.config.override" > "$checks/.config.old"
    awk '!/INITRAMFS/' "$checks/.config.old" > "$checks/.config.set"
    printf '%s\n' 'CONFIG_INITRAMFS_SOURCE=""' '# CONFIG_INITRAMFS_FORCE is not set' \
      '# CONFIG_INITRAMFS_PRESERVE_MTIME is not set' >> "$checks/.config.set"
    actual=$(grep '=[ym]' "$checks/.config.set" | LC_ALL=C sort | md5sum); actual=${actual%% *}
    printf '%s\n' "$actual" > "$checks/vermagic"
    [ "$actual" = "$abi" ] || fail "编译前内核 ABI 不一致：预检 $actual，官方 $abi；请查看 official-abi/preflight"
    echo "通过：编译前内核配置 ABI 与官方一致 $version~$abi"
    ;;
  feed)
    expected_kernel
    dest=$src/files/etc/apk/repositories.d
    mkdir -p "$dest"
    tmp=$(mktemp "$dest/.pwrt-kmods.XXXXXX")
    trap 'rm -f "$tmp"' EXIT
    printf '%s\n' "$base/kmods/$version-1-$abi/packages.adb" > "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "$dest/pwrt-kmods.list"
    trap - EXIT
    echo "已加入官方 kmods 源：$version-1-$abi"
    ;;
  verify)
    expected_kernel
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
