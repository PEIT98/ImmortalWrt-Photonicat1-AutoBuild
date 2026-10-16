#!/usr/bin/env python3
"""构建时修正官方 QModem stable 的 FM350 空 APN 拨号行为。"""

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
    previous_command = (
        "                    # 仅 FM350 空 APN 时查询 PDP，保留模组已选的运营商 APN。\n"
        '                    if [ "$fm350_guard" = "1" ] && { [ -z "$apn" ] || [ "$apn" = "auto" ]; }; then\n'
        '                        cgdcont_command="AT+CGDCONT?"\n'
        "                    else\n"
        '                        cgdcont_command="AT+CGDCONT=$pdp_index,\\"$pdp_type\\",\\"$apn\\""\n'
        "                    fi"
    )
    new_command = r'''                    # FM350 空 APN：只读取当前 CID，避免把 IMS 专用 CID 当成上网 APN。
                    if [ "$fm350_guard" = "1" ] && { [ -z "$apn" ] || [ "$apn" = "auto" ]; }; then
                        local fm350_pdp_entry fm350_pdp_apn fm350_imsi fm350_operator fm350_default_apn fm350_use_default=0
                        fm350_pdp_entry=$(cmd_dial_command "${at_port}" "AT+CGDCONT?" | awk -F '"' -v cid="$pdp_index" '
                            /^\+CGDCONT:/ {
                                header=$1
                                sub(/^\+CGDCONT:[[:space:]]*/, "", header)
                                sub(/,.*/, "", header)
                                if (header == cid) { print "present:" $4; exit }
                            }')
                        fm350_pdp_apn=${fm350_pdp_entry#present:}
                        # AT+CIMI 只在本地取 MCC/MNC，不记录完整 IMSI/卡号。
                        fm350_imsi=$(cmd_dial_command "${at_port}" "AT+CIMI" | tr -d '\r' | awk '/^[0-9]+$/ && length($0) >= 14 && length($0) <= 16 { print; exit }')
                        fm350_operator=$(printf '%s' "$fm350_imsi" | cut -c1-5)
                        # 默认 APN 对照官方 QModem apns.json；未知 SIM 不猜测。
                        case "$fm350_operator" in
                            46001|46009) fm350_default_apn=3gnet ;;
                            46000|46002|46004|46007|46008|46013) fm350_default_apn=cmnet ;;
                            46003|46011) fm350_default_apn=ctnet ;;
                            46015) fm350_default_apn=cbnet ;;
                        esac
                        if [ "$fm350_pdp_entry" = "present:" ] && [ -n "$fm350_default_apn" ]; then
                            fm350_use_default=1
                        else
                            # 换卡后只更新旧运营商的通用 APN，保留物联网/企业专用 APN。
                            case "$fm350_pdp_apn" in
                                3gnet|cmnet|ctnet|cbnet)
                                    if [ -n "$fm350_pdp_entry" ] && [ -n "$fm350_default_apn" ] && [ "$fm350_pdp_apn" != "$fm350_default_apn" ]; then
                                        fm350_use_default=1
                                    fi
                                    ;;
                            esac
                        fi
                        if [ "$fm350_use_default" = "1" ]; then
                            cgdcont_command="AT+CGDCONT=$pdp_index,\"$pdp_type\",\"$fm350_default_apn\""
                            m_debug "FM350 auto APN for SIM operator $fm350_operator: $fm350_default_apn"
                        else
                            # 未识别运营商或已有专用 APN 时只查询，不覆写模组 PDP。
                            cgdcont_command="AT+CGDCONT?"
                            if [ "$fm350_pdp_entry" = "present:" ] && [ -z "$fm350_default_apn" ]; then
                                m_debug "FM350 CID $pdp_index has no APN and SIM operator is unknown; configure APN manually"
                            fi
                        fi
                    else
                        cgdcont_command="AT+CGDCONT=$pdp_index,\"$pdp_type\",\"$apn\""
                    fi'''

    if model_guard in dial and new_fallback in dial and new_command in dial:
        if dial.count(model_guard) != 1 or dial.count(new_fallback) != 1 or dial.count(new_command) != 1:
            raise ValueError("FM350 补丁已部分应用，停止构建")
        return source

    # 只修改 fibocom/mediatek 分支；兼容未打补丁和已打旧补丁的源码。
    vendor = dial.index('        "fibocom")')
    mediatek = dial.index('                "mediatek")', vendor)
    next_platform = dial.index('                "lte")', mediatek)
    branch = dial[mediatek:next_platform]
    if branch.count('at_command="AT+CGACT=1,$pdp_index"') != 1:
        raise ValueError("上游 FM350 激活命令已变化，停止应用补丁")
    if branch.count(old_fallback) == 1 and branch.count(old_command) == 1 and model_guard not in branch:
        changed = branch.replace('                "mediatek")\n', '                "mediatek")\n' + model_guard, 1)
        changed = changed.replace(old_fallback, new_fallback).replace(old_command, new_command)
    elif branch.count(model_guard) == 1 and branch.count(new_fallback) == 1 and branch.count(previous_command) == 1:
        changed = branch.replace(previous_command, new_command)
    else:
        raise ValueError("上游 FM350 APN 逻辑已变化或补丁不完整，停止应用补丁")
    dial = dial[:mediatek] + changed + dial[next_platform:]
    result = source[:start] + dial + source[end:]
    if result.count(model_guard) != 1 or result.count(new_fallback) != 1 or result.count(new_command) != 1:
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
        print("已修复 FM350 空 APN 拨号：保留现有 PDP 或按 SIM 运营商补全 APN")
    else:
        print("FM350 APN 补丁已存在")


if __name__ == "__main__":
    main()
