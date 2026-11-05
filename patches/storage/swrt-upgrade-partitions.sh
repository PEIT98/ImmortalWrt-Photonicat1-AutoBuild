# SPDX-License-Identifier: AGPL-3.0-only
# Based on SlAlot/ImmortalWrt_Photonicat1 ae655185.
# A grown root partition is compatible with the same image layout. Keep its
# existing end sector; all image partition starts and the boot size must match.
swrt_partition_difference() {
    awk '
        FNR == NR {
            if (NF != 3 || $1 !~ /^[1-9][0-9]*$/ || $2 !~ /^[0-9]+$/ ||
                $3 !~ /^[0-9]+$/ || $3 <= 0 || ($1 in start)) bad=1
            start[$1]=$2; size[$1]=$3; next
        }
        {
            count++
            if ($1 != 1 && $1 != 2) bad=1
            if ($2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]+$/ || $3 <= 0) bad=1
            if (!($1 in start) || start[$1] != $2) bad=1
            if ($1 == 2) { root++; if (size[$1] < $3) bad=1 }
            else { boot++; if (size[$1] != $3) bad=1 }
        }
        END {
            if (!("1" in start) || !("2" in start)) bad=1
            for (p in start)
                for (q in start)
                    if (p != q && start[p] < start[q] + size[q] &&
                        start[q] < start[p] + size[p]) bad=1
            if (bad || count != 2 || root != 1 || boot != 1)
                print "Incompatible partition layout"
        }
    ' "$1" "$2"
}
