#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# eval-nonliteral — eval in command position whose argument holds an
# expansion ($var, $(cmd), `cmd`) outside single quotes. eval re-parses its
# argument as shell code, so whatever the expansion yields runs as code.
. "$(dirname -- "$0")/../lib.sh"
cc_setup eval-nonliteral "$@"
cc_awk shell <<'EOF'
{
    s = code($0)
    if (s == "")
        next
    done_ = ""
    t = s
    while (match(t, /(^|[^A-Za-z0-9_.\/-])eval([ \t]|$)/)) {
        e = RSTART
        if (substr(t, e, 4) != "eval")
            e++
        before = done_ substr(t, 1, e - 1)
        args = substr(t, e + 4)
        done_ = before "eval"
        t = args
        sub(/[ \t]+$/, "", before)
        if (before != "" && before !~ /([;&|({`]|\$\(|(^|[ \t])(then|do|else|if|elif|while|until|!))$/)
            continue
        gsub(/'[^']*'/, "", args)
        if (args ~ /[$`]/) {
            hit("eval re-parses its argument as code, so data becomes commands: use case, set --, printf or read instead")
            next
        }
    }
}
EOF
cc_finish
