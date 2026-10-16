#!/usr/bin/env python3
"""构建时修正官方 QModem stable 对 FM350 空 APN 的覆盖行为。"""

from pathlib import Path
import sys


def patch_source(source: str) -> str:
    start_marker = "\nat_dial()\n{\n"
    end_marker = "\nat_auto_dial()\n{\n"
    if source.count(start_marker) != 1 or source.count(end_marker) != 1:
        raise ValueError("上游拨号函数结构已变化，停止应用 FM350 补丁")

    start = source.index(start_marker)
    end = source.index(end_marker, start)
    dial = source[start:end]
    old_fallback = '                        [ "$apn" = "auto" ] || [ -z "$apn" ] && apn="cbnet"'
    old_command = '                    cgdcont_command="AT+CGDCONT=$pdp_index,\\"$pdp_type\\",\\"$apn\\""'
    model_guard = (
        "                    local fm350_model fm350_guard=0\n"
        '                    config_get fm350_model "$modem_config" name\n'
        '                    case "$fm350_model" in\n'
        "                        fm350*|FM350*|rw350r*|RW350R*) fm350_guard=1 ;;\n"
        "                    esac\n"
    )
    new_fallback = (
        '                        if [ "$fm350_guard" != "1" ]; then\n'
        '                            [ "$apn" = "auto" ] || [ -z "$apn" ] && apn="cbnet"\n'
        "                        fi"
    )
    new_command = (
        "                    # 仅 FM350 空 APN 时查询 PDP，保留模组已选的运营商 APN。\n"
        '                    if [ "$fm350_guard" = "1" ] && { [ -z "$apn" ] || [ "$apn" = "auto" ]; }; then\n'
        '                        cgdcont_command="AT+CGDCONT?"\n'
        "                    else\n"
        '                        cgdcont_command="AT+CGDCONT=$pdp_index,\\"$pdp_type\\",\\"$apn\\""\n'
        "                    fi"
    )

    if model_guard in dial and new_fallback in dial and new_command in dial:
        if dial.count(model_guard) != 1 or dial.count(new_command) != 1:
            raise ValueError("FM350 补丁已部分应用，停止构建")
        return source

    if dial.count(old_fallback) != 1 or dial.count(old_command) != 1:
        raise ValueError("上游 FM350 APN 拨号逻辑已变化，停止应用补丁")

    # 只修改 fibocom/mediatek 分支。其他模组、手填 APN 的逻辑保持原样。
    vendor = dial.index('        "fibocom")')
    mediatek = dial.index('                "mediatek")', vendor)
    next_platform = dial.index('                "lte")', mediatek)
    branch = dial[mediatek:next_platform]
    if branch.count(old_fallback) != 1 or branch.count(old_command) != 1:
        raise ValueError("FM350 逻辑不在预期的 fibocom/mediatek 分支")

    changed = branch.replace('                "mediatek")\n', '                "mediatek")\n' + model_guard, 1)
    changed = changed.replace(old_fallback, new_fallback).replace(old_command, new_command)
    dial = dial[:mediatek] + changed + dial[next_platform:]
    result = source[:start] + dial + source[end:]
    if result.count(model_guard) != 1 or result.count(new_command) != 1:
        raise ValueError("FM350 补丁验证失败")
    return result


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("用法: fm350-preserve-apn.py <ImmortalWrt 源码目录>")
    path = (Path(sys.argv[1]) / "feeds/qmodem/application/qmodem/files/usr/share/qmodem/modem_dial.sh")
    if not path.is_file():
        raise SystemExit(f"找不到官方 QModem stable 拨号脚本: {path}")
    original = path.read_text(encoding="utf-8")
    try:
        patched = patch_source(original)
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
    if patched != original:
        path.write_text(patched, encoding="utf-8")
        print("已修复 FM350 空 APN 清空 PDP 的问题")
    else:
        print("FM350 APN 补丁已存在")


if __name__ == "__main__":
    main()
