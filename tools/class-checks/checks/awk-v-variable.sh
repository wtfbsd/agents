#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# awk-v-variable — awk -v NAME=VALUE where VALUE comes from a variable or a
# command. awk processes backslash escapes in -v values, so a\nb becomes two
# lines and a trailing backslash eats the next character: data changes on
# the way in. Export the value and read ENVIRON["NAME"].
. "$(dirname -- "$0")/../lib.sh"
cc_setup awk-v-variable "$@"
cc_awk code <<'EOF'
FNR == 1 { inawk = 0 }
{
    s = code($0)
    if (s == "") { inawk = 0; next }
    if (s ~ /(^|[ \t;&|(`"'\/])[gmn]?awk([ \t]|$)/)
        inawk = 1
    if (inawk) {
        t = s
        while (match(t, /(^|[ \t])-v[ \t]*[A-Za-z_][A-Za-z0-9_]*=/)) {
            t = substr(t, RSTART + RLENGTH)
            if (t ~ /^'/)
                continue
            if (t ~ /^"/)
                match(t, /^"([^"\\]|\\.)*"?/)
            else
                match(t, /^[^ \t]*/)
            if (substr(t, 1, RLENGTH) ~ /[$`]/) {
                hit("awk -v interprets backslash escapes in the value: export it and read ENVIRON[\"NAME\"] instead")
                break
            }
        }
    }
    if (s !~ /\\$/)
        inawk = 0
}
EOF
cc_finish
