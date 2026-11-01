#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# tmp-predictable — temporary names another user can guess: mktemp with no
# template, a template with fewer than six X's, mktemp -u (prints a name,
# creates nothing), python tempfile.mktemp(), and fixed names in /tmp,
# /var/tmp or $TMPDIR (including name.$$). Names held in a variable
# (/tmp/$name), mktemp templates (XXXXXX) and globs or regexes that match
# mktemp's output (/tmp/name.??????, /tmp/name\.) are not flagged.
. "$(dirname -- "$0")/../lib.sh"
cc_setup tmp-predictable "$@"
cc_awk code <<'EOF'
# mktemp_args(s) — the arguments of the first mktemp in command position,
# or "\001" when there is none
function mktemp_args(s,    n, i) {
    n = segs(s, seg)
    for (i = 1; i <= n; i++)
        if (word(seg[i]) && base(W) == "mktemp")
            return R
    return "\001"
}
function fixed(t, re,    tok, rest) {
    while (match(t, re)) {
        tok = substr(t, RSTART, RLENGTH)
        t = substr(t, RSTART + RLENGTH)
        rest = tok
        sub(/^[^\/]*\//, "", rest)
        if (tok ~ /\/(var\/)?tmp\//)
            sub(/^(var\/)?tmp\//, "", rest)
        if (rest == "" || rest ~ /^\$\{?[A-Za-z_]/ || tok ~ /XXXXXX/ || tok ~ /[*?[\\]/)
            continue
        return 1
    }
    return 0
}
{
    s = code($0)
    if (s == "")
        next
    if (FILENAME ~ /\.py$/) {
        if (s ~ /(^|[^A-Za-z0-9_])mktemp[ \t]*\(/) {
            hit("tempfile.mktemp() returns a name another user can take first: use tempfile.mkstemp() or NamedTemporaryFile()")
            next
        }
    } else if (s ~ /mktemp/ && (a = mktemp_args(s)) != "\001") {
        sub(/[)`;|&].*$/, "", a)
        k = split(a, tok, /[ \t]+/)
        hasu = 0; hast = 0; tmpl = ""
        for (j = 1; j <= k; j++) {
            x = tok[j]
            if (x == "")
                continue
            if (x == "--") { tmpl = tok[j + 1]; break }
            if (x ~ /^-[A-Za-z]+$/) {
                if (x ~ /u/) hasu = 1
                if (x ~ /t/) { hast = 1; if (tok[j + 1] !~ /^-/) j++ }
                if (x ~ /p/) j++
                continue
            }
            if (x ~ /^--/) continue
            tmpl = x
            break
        }
        gsub(/["']/, "", tmpl)
        if (hasu) {
            hit("mktemp -u only prints a name, so another user can create it first: drop -u and use the file mktemp creates")
            next
        }
        if (tmpl == "" && !hast) {
            hit("mktemp without a template: give one, mktemp \"${TMPDIR:-/tmp}/NAME.XXXXXXXX\" (add -d for a directory)")
            next
        }
        if (tmpl != "" && tmpl !~ /XXXXXX$/ && !(tmpl ~ /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$/)) {
            hit("mktemp template needs at least six trailing X's: NAME.XXXXXXXX")
            next
        }
    }
    if (fixed(s, "(^|[ \t\"'=:(<>-])/(var/)?tmp/[^ \t\"'`;|&)<>]*") ||
        fixed(s, "\\$(TMPDIR|\\{TMPDIR(:?[-=][^}]*)?\\})/[^ \t\"'`;|&)<>]*")) {
        hit("fixed name in a shared temp directory: another user can create it first or plant a symlink: use mktemp \"${TMPDIR:-/tmp}/NAME.XXXXXXXX\"")
        next
    }
}
EOF
cc_finish
