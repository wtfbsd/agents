#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# run.sh — run every class check over one or more repositories.
#
#   sh tools/class-checks/run.sh [REPO_DIR...]      (default: .)
#
# Prints one line per hit, path:line: CLASS: what to do instead (paths
# prefixed with REPO_DIR/ unless REPO_DIR is "."), then a summary per repo
# on stderr. Exit 0: no hits; 1: hits; 2: could not look (a missing
# directory, a malformed allow-list, a file it cannot read, a missing tool,
# any check whose scan failed). 2 wins over 1.
#
# CLASS_CHECKS_ALLOW_MISSING=shellcheck: on a host that cannot have
# the shellcheck program, its two classes say they skipped and exit 0, not 2.
#
# Allow-list: REPO_DIR/.class-checks-allow, one entry per line,
#   CLASS PATH:LINE REASON...
# CLASS is a check name or *; PATH is relative to the repo and may use * and
# ? globs (* also crosses /); LINE is a number or *; REASON is at least two
# words saying why the hit is safe. # starts a comment line. An entry that
# hides nothing is reported as stale.

set -eu

cc_lib=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
. "$cc_lib/lib.sh"

classes=
for f in "$cc_lib"/checks/*.sh; do
    c=${f##*/}
    classes="$classes ${c%.sh}"
done
CC_CLASSES=$classes
export CC_CLASSES

[ $# -gt 0 ] || set -- .

top=$(mktemp -d "${TMPDIR:-/tmp}/class-checks-run.XXXXXXXX")
trap 'rm -rf "$top"' EXIT
trap 'rm -rf "$top"; exit 2' HUP INT TERM

status=0
n=0
for repo in "$@"; do
    n=$((n + 1))
    if [ "$repo" = . ]; then CC_PREFIX=; else CC_PREFIX=${repo%/}/; fi
    export CC_PREFIX
    if [ ! -d "$repo" ]; then
        printf 'class-checks: %s: not a directory\n' "$repo" >&2
        status=2
        continue
    fi
    CC_WORK=$top/$n
    export CC_WORK
    mkdir "$CC_WORK" || exit 2
    cc_index "$repo" "$CC_WORK" || { printf 'class-checks: %s: cannot list or read its files; could not look\n' "$repo" >&2; status=2; continue; }

    : > "$CC_WORK/allow"
    if [ -f "$repo/.class-checks-allow" ]; then
        awk '
        function glob2re(g,    r, i, ch) {
            r = "^"
            for (i = 1; i <= length(g); i++) {
                ch = substr(g, i, 1)
                if (ch == "*") r = r ".*"
                else if (ch == "?") r = r "."
                else if (index("\\.[](){}+^$|", ch)) r = r "\\" ch
                else r = r ch
            }
            return r "$"
        }
        function err(m) {
            printf "E\t%s.class-checks-allow:%d: %s\n", ENVIRON["CC_PREFIX"], FNR, m
        }
        BEGIN {
            k = split(ENVIRON["CC_CLASSES"], c, " ")
            for (i = 1; i <= k; i++) known[c[i]] = 1
            known["*"] = 1
        }
        /^[ \t]*(#|$)/ { next }
        {
            if (!($1 in known)) { err("unknown class " $1); next }
            if ($2 !~ /.:([0-9]+|\*)$/) { err("want PATH:LINE (LINE a number or *), got " $2); next }
            if (NF < 4) { err("needs a written reason (at least two words) after " $2); next }
            path = $2; sub(/:[^:]*$/, "", path)
            line = $2; sub(/^.*:/, "", line)
            printf "A\t%d\t%s\t%s\t%s\n", FNR, $1, glob2re(path), line
        }' "$repo/.class-checks-allow" > "$CC_WORK/allow.raw" || {
            printf 'class-checks: %s: cannot read .class-checks-allow; could not look\n' "$repo" >&2
            status=2
            continue
        }
        if grep -q '^E' "$CC_WORK/allow.raw"; then
            sed -n 's/^E\t//p' "$CC_WORK/allow.raw" >&2
            printf 'class-checks: %s: fix the allow-list first; not checked\n' "$repo" >&2
            status=2
            continue
        fi
        sed -n 's/^A\t//p' "$CC_WORK/allow.raw" > "$CC_WORK/allow" || exit 2
    fi

    : > "$CC_WORK/hits"
    for c in $classes; do
        rc=0
        sh "$cc_lib/checks/$c.sh" "$repo" >> "$CC_WORK/hits" || rc=$?
        if [ "$rc" -gt 1 ]; then
            printf 'class-checks: %s: check %s could not look (exit %d)\n' "$repo" "$c" "$rc" >&2
            status=2
        fi
    done

    CC_WARN=$CC_WORK/warn CC_COUNT=$CC_WORK/count
    export CC_WARN CC_COUNT
    awk -F '\t' '
    FILENAME == ARGV[1] { na++; aline[na] = $1; acls[na] = $2; are[na] = $3; aln[na] = $4; next }
    {
        i = index($0, ":"); path = substr($0, 1, i - 1); r = substr($0, i + 1)
        i = index(r, ":"); ln = substr(r, 1, i - 1); r = substr(r, i + 2)
        i = index(r, ":"); cls = substr(r, 1, i - 1)
        ok = 0
        for (a = 1; a <= na; a++)
            if ((acls[a] == "*" || acls[a] == cls) && (aln[a] == "*" || aln[a] == ln) && path ~ are[a]) {
                used[a] = 1
                ok = 1
            }
        if (ok) nallow++
        else { print ENVIRON["CC_PREFIX"] $0; nhit++ }
    }
    END {
        for (a = 1; a <= na; a++)
            if (!used[a])
                printf "%s.class-checks-allow:%d: stale: hides no hit; remove it\n", ENVIRON["CC_PREFIX"], aline[a] > ENVIRON["CC_WARN"]
        printf "%d %d\n", nhit, nallow > ENVIRON["CC_COUNT"]
    }' "$CC_WORK/allow" "$CC_WORK/hits" || {
        printf 'class-checks: %s: cannot apply the allow-list; could not look\n' "$repo" >&2
        status=2
        continue
    }
    [ ! -s "$CC_WORK/warn" ] || cat "$CC_WORK/warn" >&2
    read -r nhit nallow < "$CC_COUNT" || exit 2
    printf 'class-checks: %s: %d hits, %d allowed\n' "$repo" "$nhit" "$nallow" >&2
    if [ "$nhit" -gt 0 ] && [ "$status" -eq 0 ]; then status=1; fi
done
exit "$status"
