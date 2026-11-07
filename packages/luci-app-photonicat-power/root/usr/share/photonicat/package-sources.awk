# SPDX-License-Identifier: GPL-3.0-or-later
# Rewrite recognized URL origins only. Preserve paths, tags, whitespace and comments.
BEGIN {
    origins["official"] = "^https?://downloads[.]immortalwrt[.]org"
    origins["nju"] = "^https?://mirrors?[.]nju[.]edu[.]cn/immortalwrt"
    origins["ustc"] = "^https?://((cmcc|chinanet|cernet)[.])?mirrors[.]ustc[.]edu[.]cn/immortalwrt"
    origins["sjtu"] = "^https?://(mirrors?[.]sjtu[.]edu[.]cn|mirrors[.]sjtug[.]sjtu[.]edu[.]cn)/immortalwrt"
    origins["zju"] = "^https?://mirrors[.]zju[.]edu[.]cn/immortalwrt"
    origins["vsean"] = "^https?://mirrors[.]vsean[.]net/openwrt"
    origins["cernet"] = "^https?://mirrors[.]cernet[.]edu[.]cn/openwrt"
}
function rewrite(token,    result, kind, recognized) {
    result = token
    for (kind in origins) {
        if (token ~ (origins[kind] "(/|$)")) {
            counts[kind]++
            # These five channels are local build feeds, not published indexes on
            # ImmortalWrt mirrors. Keep the original line as a comment for recovery.
            if (token ~ /\/packages\/aarch64_generic\/(istore|openclash|qmodem|qmodem_generic|video)\/packages[.]adb$/) {
                disable = 1
                changed++
                recognized = 1
                break
            }
            sub(origins[kind], destination, result)
            recognized = 1
            break
        }
    }
    if (!recognized && token ~ /^https?:\/\//) other++
    if (result != token) changed++
    return result
}
{
    disable = 0
    rest = $0
    output = ""
    while (match(rest, /[^[:space:]]+/)) {
        prefix = substr(rest, 1, RSTART - 1)
        token = substr(rest, RSTART, RLENGTH)
        rest = substr(rest, RSTART + RLENGTH)
        output = output prefix
        if (substr(token, 1, 1) == "#") {
            output = output token rest
            rest = ""
            break
        }
        output = output rewrite(token)
    }
    if (mode == "rewrite") {
        if (disable) print "# Pwrt-disabled-unavailable " $0
        else print output rest
    }
}
END {
    if (mode != "rewrite")
        print counts["official"] + 0, counts["nju"] + 0, counts["ustc"] + 0,
            counts["sjtu"] + 0, counts["zju"] + 0, counts["vsean"] + 0,
            counts["cernet"] + 0, other + 0, changed + 0
}
