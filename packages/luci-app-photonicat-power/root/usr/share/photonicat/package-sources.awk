# SPDX-License-Identifier: GPL-3.0-or-later
# Rewrite recognized URL origins only. Preserve paths, tags, whitespace and comments.
BEGIN {
    origins["official"] = "^https?://downloads[.]immortalwrt[.]org"
    origins["nju"] = "^https?://mirrors?[.]nju[.]edu[.]cn/immortalwrt"
    origins["ustc"] = "^https?://((cmcc|chinanet|cernet)[.])?mirrors[.]ustc[.]edu[.]cn/immortalwrt"
    origins["sjtu"] = "^https?://(mirrors?[.]sjtu[.]edu[.]cn|mirrors[.]sjtug[.]sjtu[.]edu[.]cn)/immortalwrt"
    origins["zju"] = "^https?://mirrors[.]zju[.]edu[.]cn/immortalwrt"
    origins["vsean"] = "^https?://mirrors[.]vsean[.]net/openwrt"
}
function rewrite(token,    result, kind, recognized) {
    result = token
    for (kind in origins) {
        if (token ~ (origins[kind] "(/|$)")) {
            counts[kind]++
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
    if (mode == "rewrite") print output rest
}
END {
    if (mode != "rewrite")
        print counts["official"] + 0, counts["nju"] + 0, counts["ustc"] + 0,
            counts["sjtu"] + 0, counts["zju"] + 0, counts["vsean"] + 0, other + 0, changed + 0
}
