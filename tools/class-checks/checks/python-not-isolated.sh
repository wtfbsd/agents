#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# python-not-isolated — python run without -I. Without it python puts the
# current or script directory first on sys.path and honours PYTHONPATH,
# PYTHONSTARTUP and friends, so a planted json.py or a caller's environment
# runs as whoever runs python (root, in our rc.d and install scripts).
# Flags python/python3/python3.N in command position in shell scripts and
# build files (Makefile, *.mk, Jenkinsfile, YAML), and python shebangs without -I under bin/, sbin/, libexec/, rc.d/, tools/
# and in *-install files.
. "$(dirname -- "$0")/../lib.sh"
cc_setup python-not-isolated "$@"
CC_SHELL_LIST=$CC_WORK/shell
export CC_SHELL_LIST
cc_awk code <<'EOF'
BEGIN {
    while ((getline f < ENVIRON["CC_SHELL_LIST"]) > 0)
        shell[f] = 1
}
FNR == 1 {
    cmdfile = (FILENAME in shell) || base(FILENAME) ~ /^(GNUmakefile|[Mm]akefile.*|Jenkinsfile.*|.*\.(mk|ya?ml|groovy|jenkinsfile))$/
}
FNR == 1 && /^#!/ && /python/ {
    if ((FILENAME ~ /(^|\/)(bin|sbin|libexec|rc\.d|tools)\// || base(FILENAME) ~ /-install(\.[A-Za-z0-9]+)?$/) &&
        $0 !~ /python[0-9.]*[ \t]+-[A-Za-z]*I/)
        hit("python shebang without -I in a script that may run as root: use #!/usr/local/bin/python3 -I (or #!/usr/bin/env -S python3 -I)")
    next
}
# commands live in shell scripts and build files; a package list naming
# python3 is not running it
!cmdfile { next }
{
    s = code($0)
    if (s == "")
        next
    n = segs(s, seg)
    for (i = 1; i <= n; i++) {
        if (!word(seg[i]) || W !~ /(^|\/)python[0-9]*(\.[0-9]+)?$/)
            continue
        if (R ~ /^[ \t]+(-[A-Za-z]*I|-V([ \t]|$)|--version)/)
            continue
        hit("python without -I imports from the current/script directory and honours PYTHON* variables: run python3 -I ...")
        next
    }
}
EOF
cc_finish
