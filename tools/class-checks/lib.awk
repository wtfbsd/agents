# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# lib.awk — helpers shared by the class checks. cc_awk (lib.sh) puts this in
# front of each check's own program. The class name comes from ENVIRON, never
# from awk -v (which would interpret backslashes).

function hit(msg) {
    printf "%s:%d: %s: %s\n", FILENAME, FNR, ENVIRON["CC_CLASS"], msg
}

# code(s) — the line without its shell comment; "" for a comment line
function code(s) {
    if (s ~ /^[ \t]*#/)
        return ""
    sub(/[ \t]+#.*$/, "", s)
    return s
}

function base(p) {
    sub(/.*\//, "", p)
    return p
}

# rootrun(p) — a file that runs as root: under rc.d/, sbin/ or libexec/, or
# named *-install
function rootrun(p) {
    return p ~ /(^|\/)(rc\.d|sbin|libexec)\// || base(p) ~ /-install(\.[A-Za-z0-9]+)?$/
}

# segs(s, seg) — split s into simple-command segments (at ; & | && || $( `
# and at a ( or { that starts a word; ${...} stays whole), each with what
# sits in front of the
# command removed: a case pattern "pat)", keywords (then, do, if, !, ...), wrappers (exec, doas,
# sudo, env, nohup, nice, time) and their options, NAME=value assignments,
# and the YAML/Jenkinsfile wrappers "- ", "run:", sh '...'. A trailing \
# (line continuation) is dropped first. Returns the count.
# qmask(s) — s with the separators ; & | ( { inside quotes replaced by
# \004-\010, so "need (python3)" is not taken for a command; a $( inside
# double quotes is a real command and stays
function qmask(s,    i, c, out, q, n) {
    out = ""; q = ""; n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q != "'" && c == "\\") { out = out c substr(s, i + 1, 1); i++; continue }
        if (q == "" && (c == "'" || c == "\"")) q = c
        else if (q != "" && c == q) q = ""
        else if (q != "" && index(";&|({", c) && !(q == "\"" && c == "(" && substr(s, i - 1, 1) == "$"))
            c = sprintf("%c", 3 + index(";&|({", c))
        out = out c
    }
    return out
}
function qunmask(t) {
    gsub(/\004/, ";", t); gsub(/\005/, "\\&", t); gsub(/\006/, "|", t)
    gsub(/\007/, "(", t); gsub(/\010/, "{", t)
    return t
}
function segs(s, seg,    n, i, t, more) {
    sub(/[ \t]*\\$/, "", s)
    while (match(s, /\$\{[^{}]*\}/))
        s = substr(s, 1, RSTART - 1) "$\002" substr(s, RSTART + 2, RLENGTH - 3) "\003" substr(s, RSTART + RLENGTH)
    s = qmask(s)
    gsub(/\$\(|`|&&|\|\||[;&|]/, "\001", s)
    gsub(/(^|[ \t\001])[({]+/, "\001", s)
    n = split(s, seg, "\001")
    for (i = 1; i <= n; i++) {
        t = seg[i]
        gsub(/\002/, "{", t)
        gsub(/\003/, "}", t)
        t = qunmask(t)
        do {
            more = 0
            sub(/^[ \t]+/, "", t)
            if (sub(/^case[ \t]+[^ \t]+[ \t]+in[ \t]+/, "", t)) more = 1
            else if (sub(/^[^ \t()"']*\)[ \t]+/, "", t)) more = 1
            else if (sub(/^(then|do|else|elif|if|while|until|!|exec|nohup|nice|time|doas|sudo)[ \t]+/, "", t)) more = 1
            else if (sub(/^env([ \t]+-[A-Za-z]+)*[ \t]+/, "", t)) more = 1
            else if (sub(/^-[ugCp][ \t]+[^ \t-][^ \t]*[ \t]+/, "", t)) more = 1
            else if (sub(/^-[A-Za-z]+[ \t]+/, "", t)) more = 1
            else if (sub(/^[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|'[^']*'|[^ \t]*)[ \t]+/, "", t)) more = 1
            else if (sub(/^-[ \t]+/, "", t)) more = 1
            else if (sub(/^(run|script|command|cmd):[ \t]*/, "", t)) more = 1
            else if (sub(/^(sh|bash|ksh)[ \t]+(-c[ \t]+)?["']+/, "", t)) more = 1
            else if (sub(/^["']+/, "", t)) more = 1
        } while (more)
        seg[i] = t
    }
    return n
}

# word(t) — split segment t into W (its command word, quotes removed, up to
# a closing paren) and R (the rest); 0 when the segment is empty
function word(t) {
    if (!match(t, /^[^ \t)]+/))
        return 0
    W = substr(t, 1, RLENGTH)
    R = substr(t, RLENGTH + 1)
    gsub(/["']/, "", W)
    return 1
}
