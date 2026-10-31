#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# ours-check.sh — the self-hosted package check.
#
# usage: ours-check.sh OURS_LIST PUBLISHED [UPSTREAM_NV PUBLISHED_NV]
#   OURS_LIST     lines "name reason note...", reason one of
#                 product meta patched options missing; '#' starts a comment
#   PUBLISHED     package names in the product repository, one per line
#   UPSTREAM_NV   optional: name-version lines of the upstream repository
#   PUBLISHED_NV  optional: name-version lines of the product repository
#
# Fails when a published package is not in OURS_LIST, when an OURS_LIST line
# has no valid reason and note, or (4-argument form) when a published
# name-version is identical to one in the upstream repository.
#
# exit 0 pass, 1 fail, 2 could not look (usage error, a file that cannot be
# read, or an input with nothing in it)
set -eu
LC_ALL=C; export LC_ALL     # one collation for sort and comm
[ $# -eq 2 ] || [ $# -eq 4 ] || {
    cat >&2 <<USAGE
usage: $0 OURS_LIST PUBLISHED [UPSTREAM_NV PUBLISHED_NV]
  OURS_LIST     ours.list: one line per self-hosted package: name, reason, note
                (reason: product meta patched options missing)
  PUBLISHED     the package names in your product repository, one per line
  UPSTREAM_NV   upstream name-version pairs, one per line (optional pair)
  PUBLISHED_NV  your product repository's name-version pairs, one per line
exit: 0 pass, 1 fail, 2 could not look (usage error, unreadable or empty input)
USAGE
    exit 2
}
for f in "$@"; do
    [ -f "$f" ] && [ -r "$f" ] || { echo "cannot read $f: could not look (pass a readable file; see the usage in the header)"; exit 2; }
done
tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT

# non-blank, non-comment first fields of a file, sorted and unique
names() { awk '!/^[[:space:]]*#/ && NF { print $1 }' "$1" | sort -u; }

st=0
awk -v bad="$tmp/bad" '!/^[[:space:]]*#/ && NF {
        if (NF < 3 || $2 !~ /^(product|meta|patched|options|missing)$/)
            print $1 > bad
        print $1
     }' "$1" | sort -u > "$tmp/listed"
[ -s "$tmp/listed" ] || { echo "no package lines read from $1: could not look (ours.list needs one line per self-hosted package: name, reason, note)"; exit 2; }
if [ -s "$tmp/bad" ]; then
    sed 's/^/ours.list line without a valid reason and note (reason must be one of: product meta patched options missing): /' "$tmp/bad"; st=1
fi
names "$2" > "$tmp/published"
[ -s "$tmp/published" ] || { echo "no published package names read from $2: could not look (list the product repository, one package name per line)"; exit 2; }
comm -23 "$tmp/published" "$tmp/listed" > "$tmp/extra"
if [ -s "$tmp/extra" ]; then
    sed 's/^/published but not in ours.list: /' "$tmp/extra"; st=1
fi
if [ $# -eq 4 ]; then
    names "$3" > "$tmp/up"
    names "$4" > "$tmp/pubnv"
    [ -s "$tmp/up" ] || { echo "no upstream name-versions read from $3: could not look (list upstream name-version pairs, one per line)"; exit 2; }
    [ -s "$tmp/pubnv" ] || { echo "no published name-versions read from $4: could not look (list the product repository name-version pairs, one per line)"; exit 2; }
    comm -12 "$tmp/up" "$tmp/pubnv" > "$tmp/same"
    if [ -s "$tmp/same" ]; then
        sed 's/^/identical to upstream, take it from upstream: /' "$tmp/same"; st=1
    fi
fi
[ "$st" -eq 0 ] && echo "ours-check: pass ($(wc -l < "$tmp/published" | tr -d ' ') self-hosted packages, each with a reason)"
exit "$st"
