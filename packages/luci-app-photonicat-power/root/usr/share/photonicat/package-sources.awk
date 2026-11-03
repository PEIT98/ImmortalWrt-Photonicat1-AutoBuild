# SPDX-License-Identifier: GPL-3.0-or-later
# Rewrite recognized URL origins only. Preserve paths, tags, whitespace and comments.
function rewrite(token,    result) {
    result = token
    if (token ~ /^https?:\/\/downloads[.]immortalwrt[.]org(\/|$)/) {
        official++
        sub(/^https?:\/\/downloads[.]immortalwrt[.]org/, destination, result)
    } else if (token ~ /^https?:\/\/mirrors?[.]nju[.]edu[.]cn\/immortalwrt(\/|$)/) {
        nju++
        sub(/^https?:\/\/mirrors?[.]nju[.]edu[.]cn\/immortalwrt/, destination, result)
    } else if (token ~ /^https?:\/\//) {
        other++
    }
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
    if (mode != "rewrite") print official + 0, nju + 0, other + 0, changed + 0
}
