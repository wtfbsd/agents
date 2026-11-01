# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# lib.sh — shared by the class checks; sourced, never run.
#
# A check is `checks/CLASS.sh REPO_DIR`. It prints one line per hit,
#   path:line: CLASS: what to do instead
# with path relative to REPO_DIR, and exits 1 on any hit, 0 on none, 2 when
# it could not look: any failure while scanning (find, grep, awk, xargs,
# sort, the shellcheck program) or a missing tool is exit 2, never "no hits". The
# allow-list is applied by run.sh, not here.
#
# The file index (built once per repo; run.sh shares it through CC_WORK):
#   all    every regular file outside .git
#   text   the text files among them
#   code   text files that are not prose (md, txt, html, svg, json, ...)
#   shell  sh/ksh/bash scripts: by extension, by shebang, or under rc.d/

# cc_die MSG — could not look: say so (naming the class) and exit 2
cc_die() {
    printf 'class-checks: %s%s\n' "${CC_CLASS:+$CC_CLASS: }" "$*" >&2
    exit 2
}

# cc_list NAME — the NAME index as NUL-separated paths, for xargs -0
cc_list() {
    tr '\n' '\0' < "$CC_WORK/$1"
}

# cc_ok1 CMD... — run CMD; its exit 1 ("found something", as for grep or
# the shellcheck program) is success, 2 and above are failure. For xargs, which folds
# every non-zero status of a batch into 123.
cc_ok1='"$@"; [ "$?" -le 1 ]'

# cc_index ROOT WORK — build the file index; non-zero when any step failed
cc_index() {
    _root=$1 _w=$2
    (cd "$_root" && find . -name .git -prune -o -type f -print) > "$_w/all.raw" || return 1
    sed 's|^\./||' "$_w/all.raw" | LC_ALL=C sort > "$_w/all" || return 1
    : > "$_w/text.raw"
    if [ -s "$_w/all" ]; then
        (cd "$_root" && tr '\n' '\0' < "$_w/all" |
            xargs -0 sh -c "$cc_ok1" sh grep -lI '' --) > "$_w/text.raw" || return 1
    fi
    LC_ALL=C sort "$_w/text.raw" > "$_w/text" || return 1
    grep -Ev '(^|/)(LICENSE|COPYING)[^/]*$|\.(md|markdown|txt|rst|html?|svg|css|xml|json|log|po|pot)$' \
        "$_w/text" > "$_w/code" || [ "$?" -eq 1 ] || return 1
    : > "$_w/shell.raw"
    [ -s "$_w/code" ] || { : > "$_w/shell"; return 0; }
    (cd "$_root" && tr '\n' '\0' < "$_w/code" | xargs -0 awk '
        FNR == 1 {
            p = FILENAME
            if (p ~ /\.(sh|ksh|bash)$/ || p ~ /(^|\/)rc\.d\/[^\/]+$/ ||
                $0 ~ /^#![ \t]*[^ \t]*\/(env[ \t]+)?(sh|ksh|mksh|bash|dash|ash|zsh)([ \t]|$)/ ||
                $0 ~ /^#![ \t]*[^ \t]*\/env[ \t]+(sh|ksh|mksh|bash|dash|ash|zsh)([ \t]|$)/)
                print p
            nextfile
        }') > "$_w/shell.raw" || return 1
    LC_ALL=C sort "$_w/shell.raw" > "$_w/shell" || return 1
}

# cc_setup CLASS "$@" — check the arguments, build or reuse the index, cd
# into the repo
cc_setup() {
    CC_CLASS=$1
    shift
    export CC_CLASS
    [ $# -eq 1 ] || cc_die "usage: $CC_CLASS.sh REPO_DIR"
    [ -d "$1" ] || cc_die "$1: not a directory"
    cc_root=$(CDPATH='' cd -- "$1" && pwd -P) || exit 2
    if [ -z "${CC_WORK:-}" ] || [ ! -f "$CC_WORK/shell" ]; then
        CC_WORK=$(mktemp -d "${TMPDIR:-/tmp}/class-checks.XXXXXXXX") || exit 2
        trap 'rm -rf "$CC_WORK"' EXIT
        trap 'rm -rf "$CC_WORK"; exit 2' HUP INT TERM
        cc_index "$cc_root" "$CC_WORK" || cc_die "$1: cannot list or read its files"
    fi
    cc_out=$CC_WORK/hits.$CC_CLASS
    : > "$cc_out"
    cd "$cc_root" || exit 2
}

# cc_awk INDEX — run the awk program on stdin (after lib.awk) over every file
# in INDEX, collecting hits
cc_awk() {
    _prog=$(cat "$cc_lib/lib.awk"; cat)
    [ -s "$CC_WORK/$1" ] || return 0
    cc_list "$1" | xargs -0 awk -- "$_prog" >> "$cc_out" ||
        cc_die "the scan failed (awk over the $1 files); could not look"
}

# cc_finish — print the hits (sorted by file, then line); exit 1 on any
cc_finish() {
    [ -s "$cc_out" ] || exit 0
    LC_ALL=C sort -t: -k1,1 -k2,2n -k3 -u "$cc_out" || cc_die "cannot sort the hits"
    exit 1
}

# cc_need_shellcheck SC — return when SC (the shellcheck to use) runs.
# Without it the check could not look (exit 2), unless
# CLASS_CHECKS_ALLOW_MISSING names shellcheck (for a host that cannot have
# it): then it says it skipped and exits 0.
cc_need_shellcheck() {
    command -v "$1" >/dev/null 2>&1 && return 0
    case " $(printf '%s' "${CLASS_CHECKS_ALLOW_MISSING:-}" | tr ',' ' ') " in
    *' shellcheck '*)
        printf 'class-checks: %s: shellcheck is not installed; skipped (CLASS_CHECKS_ALLOW_MISSING)\n' "$CC_CLASS" >&2
        exit 0 ;;
    esac
    cc_die "shellcheck is not installed (could not look; set CLASS_CHECKS_ALLOW_MISSING=shellcheck to skip it on purpose)"
}

# cc_shellcheck ARGS... — shellcheck every shell file (files without a
# shebang are read as POSIX sh), output in gcc format; non-zero when
# the shellcheck program failed (its exit 1, "findings", is not a failure)
cc_shellcheck() {
    _sc=$1
    shift
    : > "$CC_WORK/sc.bang"
    : > "$CC_WORK/sc.nobang"
    while IFS= read -r _f; do
        [ -r "$_f" ] || return 1
        if head -n 1 -- "$_f" | grep -q '^#!'; then
            printf '%s\n' "$_f" >> "$CC_WORK/sc.bang"
        else
            printf '%s\n' "$_f" >> "$CC_WORK/sc.nobang"
        fi
    done < "$CC_WORK/shell"
    if [ -s "$CC_WORK/sc.bang" ]; then
        cc_list sc.bang | xargs -0 sh -c "$cc_ok1" sh "$_sc" -f gcc "$@" -- || return 1
    fi
    if [ -s "$CC_WORK/sc.nobang" ]; then
        cc_list sc.nobang | xargs -0 sh -c "$cc_ok1" sh "$_sc" -f gcc -s sh "$@" -- || return 1
    fi
    return 0
}

[ -n "${cc_lib:-}" ] || cc_lib=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)

# cc_sc_hits FILE — turn shellcheck gcc lines into hits; the message is
# CC_SC_MSG when set, else shellcheck's own, followed by the code
cc_sc_hits() {
    awk '
    match($0, /:[0-9]+:[0-9]+: [a-z]+: /) {
        path = substr($0, 1, RSTART - 1)
        pos = substr($0, RSTART + 1, RLENGTH - 1)
        msg = substr($0, RSTART + RLENGTH)
        line = pos; sub(/:.*/, "", line)
        code = ""
        if (match(msg, / \[SC[0-9]+\]$/)) {
            code = substr(msg, RSTART + 2, RLENGTH - 3)
            msg = substr(msg, 1, RSTART - 1)
        }
        if (ENVIRON["CC_SC_MSG"] != "")
            msg = ENVIRON["CC_SC_MSG"]
        printf "%s:%s: %s: %s (%s)\n", path, line, ENVIRON["CC_CLASS"], msg, code
    }' "$1" >> "$cc_out" || cc_die "cannot read the shellcheck output"
}
