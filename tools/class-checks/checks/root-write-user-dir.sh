#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# root-write-user-dir — a script that runs as root (under rc.d/, sbin/,
# libexec/, or named *-install) writing into a directory a user can write:
# $HOME (or any *home* variable), ~, /home, /tmp, /var/tmp, $TMPDIR. The
# user can plant a symlink there first and root writes through it. Flags
# > and >> redirections, and cp/mv/install/ln whose destination (last
# argument) or tee whose file is in such a directory. A heuristic: it sees
# the directory by name, not by who owns it.
. "$(dirname -- "$0")/../lib.sh"
cc_setup root-write-user-dir "$@"
cc_awk shell <<'EOF'
# a home (also behind a root prefix: "$R$_home", "$R/home/"), or a shared
# temp directory
function userdir(x) {
    return x ~ /^["']?(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?)?(\$\{?[A-Za-z_]*[Hh][Oo][Mm][Ee]|\/home\/|\/usr\/home\/)/ ||
        x ~ /^["']?(~|\/tmp(\/|["']?$)|\/var\/tmp(\/|["']?$)|\$\{?TMPDIR)/
}
FNR == 1 && !rootrun(FILENAME) { nextfile }
{
    s = code($0)
    if (s == "")
        next
    m = "root writes into a user-writable directory and follows any symlink planted there: write as that user (su -m USER -c ...), or into a fresh mktemp -d directory, refusing symlinks (test -L)"
    t = s
    while (match(t, /(^|[^0-9&<>])[0-9]?>>?[ \t]*/)) {
        t = substr(t, RSTART + RLENGTH)
        if (userdir(t)) {
            hit(m)
            next
        }
    }
    n = segs(s, seg)
    for (i = 1; i <= n; i++) {
        if (!word(seg[i]))
            continue
        c = base(W)
        if (c !~ /^(cp|mv|install|ln|tee)$/)
            continue
        k = split(R, tok, /[ \t]+/)
        found = 0
        if (c == "tee") {
            for (j = 1; j <= k; j++)
                if (tok[j] !~ /^-/ && userdir(tok[j]))
                    found = 1
        } else {
            for (j = k; j >= 1; j--)
                if (tok[j] != "") {
                    found = userdir(tok[j])
                    break
                }
        }
        if (found) {
            hit(m)
            next
        }
    }
}
EOF
cc_finish
