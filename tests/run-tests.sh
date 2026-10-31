#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# run-tests.sh — self-contained checks for the wtfbsd/agents tooling.
#
# Everything here is offline and local: it validates the Q&A contract and
# the two scripts with generated fixtures. No gh, no network, no VMs.
#
# Environment: requires awk and a POSIX sh (dash is used for the product.conf
# sourcing checks when present; set POSIX_SH to override). Run from anywhere:
#   tests/run-tests.sh            all checks
#   OURS_CHECK=/path/to/copy tests/run-tests.sh
#                                 run the ours-check cases against another
#                                 copy of ours-check.sh (to prove them red)

set -eu

progname=$(basename "$0")
here=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
repo=$(dirname "$here")
apply="$repo/scripts/apply-answers.sh"
ours=${OURS_CHECK:-$repo/scripts/ours-check.sh}
if [ -z "${POSIX_SH:-}" ]; then
    if command -v dash >/dev/null 2>&1; then POSIX_SH=dash; else POSIX_SH=sh; fi
fi

[ $# -eq 0 ] || {
    printf 'usage: %s\n' "$progname" >&2
    exit 2
}

tmp_prefix=${TMPDIR:-/tmp}
work=$(mktemp -d "$tmp_prefix/wtfbsd-agents-tests.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

pass=0
fail=0

ok() {
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$1"
}

no() {
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$1"
    shift
    while [ $# -gt 0 ]; do
        printf '      %s\n' "$1"
        shift
    done
}

# answer fixture: name FILE key=value ... — one flat line per pair
fixture() {
    _f=$1; shift
    : > "$work/$_f"
    for kv in "$@"; do
        printf '%s\n' "$kv" >> "$work/$_f"
    done
}

# Y runs a command; stdout/stderr land in $work/stdout and $work/stderr and
# the exit status is preserved in rc (set -e must not abort the harness on
# an expected failure, hence the return 0)
Y() {
    "$@" >"$work/stdout" 2>"$work/stderr" || { rc=$?; return 0; }
    rc=0
}

# --- happy path: the two example answer sets ------------------------------
Y "$apply" --check "$repo/examples/examplebsd-netbsd-answers.yaml"
if [ "$rc" -eq 0 ]; then ok "examplebsd-netbsd answers validate"; else
    no "examplebsd-netbsd answers validate" "$(cat "$work/stderr")"
fi

Y "$apply" --check "$repo/examples/examplebsd-answers.yaml"
if [ "$rc" -eq 0 ]; then ok "examplebsd-freebsd answers validate"; else
    no "examplebsd-freebsd answers validate" "$(cat "$work/stderr")"
fi

# --- product.conf generation and POSIX-sh sourcing ------------------------
Y "$apply" "$repo/examples/examplebsd-netbsd-answers.yaml" -o "$work/exnet.conf"
if [ "$rc" -eq 0 ] && [ ! -d "$work/exnet.conf" ] && [ -s "$work/exnet.conf" ]; then
    ok "examplebsd product.conf written"
else
    no "examplebsd product.conf written" "$(cat "$work/stderr")"
fi
if "$POSIX_SH" -c ". '$work/exnet.conf'" 2>/dev/null && \
   grep -q "DISTRO_NAME='ExampleBSD'" "$work/exnet.conf" && \
   grep -q "ZFS_POOL_NAME='exampledata'" "$work/exnet.conf" && \
   grep -q "FILESYSTEM_ROOT='ffs'" "$work/exnet.conf"; then
    ok "examplebsd product.conf is sourceable POSIX sh with the right keys"
else
    no "examplebsd product.conf is sourceable POSIX sh with the right keys"
fi
Y "$apply" "$repo/examples/examplebsd-netbsd-answers.yaml" -o "$work/exnet.conf"
if [ "$rc" -eq 2 ]; then
    ok "refuses to overwrite an existing product.conf without --force"
else
    no "refuses to overwrite an existing product.conf without --force" "rc=$rc"
fi
Y "$apply" "$repo/examples/examplebsd-netbsd-answers.yaml" -o "$work/exnet.conf" --force
if [ "$rc" -eq 0 ]; then
    ok "--force overwrites an existing product.conf"
else
    no "--force overwrites an existing product.conf" "$(cat "$work/stderr")"
fi

# --- defaults resolve from the per_os row ---------------------------------
fixture dfo1.yaml \
    'DISTRO_OS: netbsd' \
    'DISTRO_NAME: ExampleBSD' \
    'DISTRO_SLUG: examplebsd'
Y "$apply" --check "$work/dfo1.yaml"
if [ "$rc" -eq 0 ] && grep -q 'Q3 .*DISTRO_ARCH .*amd64 .*first of the netbsd per_os row' "$work/stdout"; then
    ok "DISTRO_ARCH defaults to the first arch of the netbsd row"
else
    no "DISTRO_ARCH defaults to the first arch of the netbsd row" "rc=$rc"
fi

# freebsd row: FILESYSTEM_ROOT default is zfs (first of the root_fs column)
fixture dfo2.yaml \
    'DISTRO_OS: freebsd' \
    'DISTRO_NAME: ExampleBSD' \
    'DISTRO_SLUG: examplebsd'
Y "$apply" --check "$work/dfo2.yaml"
if [ "$rc" -eq 0 ] && grep -q 'Q4 .*FILESYSTEM_ROOT  *zfs  *first of' "$work/stdout"; then
    ok "FILESYSTEM_ROOT defaults to zfs on freebsd"
else
    no "FILESYSTEM_ROOT defaults to zfs on freebsd" "rc=$rc, stdout: $(head -8 "$work/stdout")"
fi

# --- honesty: forbidden combinations must be refused ----------------------
fixture bad1.yaml \
    'DISTRO_OS: netbsd' 'DISTRO_NAME: ExampleBSD' 'DISTRO_SLUG: examplebsd' \
    'DISTRO_ARCH: amd64' 'FILESYSTEM_ROOT: zfs' 'INSTALLER: tui'
Y "$apply" --check "$work/bad1.yaml"
if [ "$rc" -eq 3 ]; then
    ok "netbsd root-on-ZFS is refused"
else
    no "netbsd root-on-ZFS is refused" "rc=$rc: $(cat "$work/stderr")"
fi

fixture bad2.yaml \
    'DISTRO_OS: openbsd' 'DISTRO_NAME: ExampleBSD' 'DISTRO_SLUG: examplebsd' \
    'DISTRO_ARCH: amd64' 'FILESYSTEM_ROOT: ffs' 'INSTALLER: tui' \
    'ZFS_DATA_POOL: yes' 'ZFS_POOL_NAME: exampledata'
Y "$apply" --check "$work/bad2.yaml"
if [ "$rc" -eq 3 ]; then
    ok "a ZFS data pool on OpenBSD is refused"
else
    no "a ZFS data pool on OpenBSD is refused" "rc=$rc: $(cat "$work/stderr")"
fi

fixture bad3.yaml \
    'DISTRO_OS: dragonfly' 'DISTRO_NAME: ExampleBSD' 'DISTRO_SLUG: examplebsd' \
    'DISTRO_ARCH: aarch64' 'FILESYSTEM_ROOT: hammer2' 'INSTALLER: tui'
Y "$apply" --check "$work/bad3.yaml"
if [ "$rc" -eq 3 ]; then
    ok "DragonFly on aarch64 is refused"
else
    no "DragonFly on aarch64 is refused" "rc=$rc: $(cat "$work/stderr")"
fi

fixture bad4.yaml \
    'DISTRO_OS: illumos' 'DISTRO_NAME: ExampleBSD' 'DISTRO_SLUG: examplebsd' \
    'DISTRO_ARCH: amd64' 'FILESYSTEM_ROOT: zfs' 'INSTALLER: gui'
Y "$apply" --check "$work/bad4.yaml"
if [ "$rc" -eq 3 ]; then
    ok "the GUI installer is refused on illumos (honest per_os row)"
else
    no "the GUI installer is refused on illumos (honest per_os row)" "rc=$rc: $(cat "$work/stderr")"
fi

fixture bad5.yaml \
    'DISTRO_OS: netbsd' 'DISTRO_NAME: ExampleBSD' 'DISTRO_SLUG: examplebsd' \
    'DISTRO_ARCH: amd64' 'FILESYSTEM_ROOT: ffs' 'ZFS_DATA_POOL: yes'
Y "$apply" --check "$work/bad5.yaml"
if [ "$rc" -eq 3 ]; then
    ok "ZFS_DATA_POOL=yes without a ZFS_POOL_NAME is refused"
else
    no "ZFS_DATA_POOL=yes without a ZFS_POOL_NAME is refused" "rc=$rc: $(cat "$work/stderr")"
fi

# --- validation of identifiers and values ---------------------------------
fixture bad6.yaml \
    'DISTRO_OS: netbsd' 'DISTRO_NAME: ExampleBSD' 'DISTRO_SLUG: Example_BSD'
Y "$apply" --check "$work/bad6.yaml"
if [ "$rc" -eq 3 ]; then
    ok "uppercase slug is refused"
else
    no "uppercase slug is refused" "rc=$rc: $(cat "$work/stderr")"
fi

fixture bad7.yaml \
    'DISTRO_OS: netbsd' 'DISTRO_NAME: ExampleBSD' 'DISTRO_SLUG: examplebsd' \
    'TOTALLY_UNKNOWN_KEY: oops'
Y "$apply" --check "$work/bad7.yaml"
if [ "$rc" -eq 3 ]; then
    ok "unknown answer key is refused"
else
    no "unknown answer key is refused" "rc=$rc: $(cat "$work/stderr")"
fi

fixture bad8.yaml \
    'DISTRO_OS: netbsd' 'DISTRO_NAME: a|pipe' 'DISTRO_SLUG: examplebsd'
Y "$apply" --check "$work/bad8.yaml"
if [ "$rc" -eq 3 ]; then
    ok "a record separator inside a value is refused"
else
    no "a record separator inside a value is refused" "rc=$rc: $(cat "$work/stderr")"
fi

fixture ok9.yaml \
    'DISTRO_OS: illumos' 'DISTRO_NAME: ExampleBSD' 'DISTRO_SLUG: examplebsd' \
    'PROFILE: desktop' 'PACKAGE_SET: base-desktop'
Y "$apply" --check "$work/ok9.yaml"
if [ "$rc" -eq 0 ]; then
    ok "illumos with ZFS root, defaults resolved, is valid"
else
    no "illumos with ZFS root, defaults resolved, is valid" "rc=$rc: $(cat "$work/stderr")"
fi

# --- product.conf values stay literal when sourced (no $ / ` expansion) ----
sed "s/^MOTD: .*/MOTD: it's \$(touch $(printf '%s' "$work" | sed 's/[\/&]/\\&/g')\/pwned) \`id\` costs \$0/" \
    "$repo/examples/examplebsd-answers.yaml" > "$work/inj.yaml"
Y "$apply" "$work/inj.yaml" -o "$work/inj.conf"
if [ "$rc" -eq 0 ] && got=$("$POSIX_SH" -c ". '$work/inj.conf'; printf '%s' \"\$MOTD\"") && \
   [ ! -e "$work/pwned" ] && [ "$got" = "$(sed -n 's/^MOTD: //p' "$work/inj.yaml")" ]; then
    ok "product.conf keeps \$ and backquotes literal when sourced"
else
    no "product.conf keeps \$ and backquotes literal when sourced" "rc=$rc: $(cat "$work/stderr")"
fi

# --- BRAND_COLOR takes bare RRGGBB: a leading # or 5 digits is refused -----
for bc in '"#3b6ea5"' '3b6ea'; do
    sed "s/^BRAND_COLOR: .*/BRAND_COLOR: $bc/" "$repo/examples/examplebsd-answers.yaml" > "$work/bc.yaml"
    Y "$apply" --check "$work/bc.yaml"
    if [ "$rc" -eq 3 ]; then ok "BRAND_COLOR $bc refused"; else
        no "BRAND_COLOR $bc refused" "rc=$rc"; fi
done

# --- --check ignores an existing product.conf (it writes nothing) ---------
: > "$work/product.conf"
( cd "$work" && "$apply" --check "$repo/examples/examplebsd-answers.yaml" ) >/dev/null 2>&1 && rc=0 || rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$work/product.conf" ]; then ok "--check runs beside an existing product.conf"; else
    no "--check runs beside an existing product.conf" "rc=$rc"; fi

# --- ours-check.sh: the self-hosted package check -------------------------
fixture ours.list \
    '# ours.list: every package the product repository publishes, and why' \
    'examplebsd-artwork    product  wallpapers, logo, greeter theme' \
    'examplebsd-desktop    meta     pulls the desktop from upstream' \
    '' \
    'examplebsd-firstboot  product  first-boot account helper'
fixture published.txt 'examplebsd-artwork' 'examplebsd-desktop' 'examplebsd-firstboot'
fixture published.nv 'examplebsd-artwork-1.0.20261031.1' 'examplebsd-desktop-1.0.20261031.1' \
    'examplebsd-firstboot-1.0.20261031.1'
fixture upstream.nv 'xorg-7.7_3' 'xfce-4.20' 'lightdm-1.32.0_6' 'firefox-140.0,2'

Y sh "$ours" "$work/ours.list" "$work/published.txt"
if [ "$rc" -eq 0 ] && grep -q 'pass (3 self-hosted' "$work/stdout"; then
    ok "ours-check: a valid ours.list and published list pass (2-arg form)"
else
    no "ours-check: a valid ours.list and published list pass (2-arg form)" "rc=$rc: $(cat "$work/stdout")"
fi

Y sh "$ours" "$work/ours.list" "$work/published.txt" "$work/upstream.nv" "$work/published.nv"
if [ "$rc" -eq 0 ] && grep -q 'pass (3 self-hosted' "$work/stdout"; then
    ok "ours-check: nothing identical to upstream passes (4-arg form)"
else
    no "ours-check: nothing identical to upstream passes (4-arg form)" "rc=$rc: $(cat "$work/stdout")"
fi

# red: a published package that ours.list does not name
cp "$work/published.txt" "$work/pub-extra.txt"
printf '%s\n' 'xorg' >> "$work/pub-extra.txt"
Y sh "$ours" "$work/ours.list" "$work/pub-extra.txt"
if [ "$rc" -eq 1 ] && grep -q '^published but not in ours.list: xorg$' "$work/stdout"; then
    ok "ours-check: a published package missing from ours.list fails"
else
    no "ours-check: a published package missing from ours.list fails" "rc=$rc: $(cat "$work/stdout")"
fi

# red: a line whose reason is not in the table, and a line with no note
for line in 'examplebsd-artwork    easier   we wanted to' 'examplebsd-artwork    product'; do
    { grep -v '^examplebsd-artwork' "$work/ours.list"; printf '%s\n' "$line"; } > "$work/ours-bad.list"
    Y sh "$ours" "$work/ours-bad.list" "$work/published.txt"
    if [ "$rc" -eq 1 ] && grep -q '^ours.list line without a valid reason and note (reason must be one of: product meta patched options missing): examplebsd-artwork$' "$work/stdout"; then
        ok "ours-check: line '$line' fails"
    else
        no "ours-check: line '$line' fails" "rc=$rc: $(cat "$work/stdout")"
    fi
done

# red: a published package identical in name and version to upstream's
fixture ours-up.list 'examplebsd-artwork product wallpapers' 'lightdm patched fix not shipped yet'
fixture pub-up.txt 'examplebsd-artwork' 'lightdm'
fixture pub-up.nv 'examplebsd-artwork-1.0.20261031.1' 'lightdm-1.32.0_6'
Y sh "$ours" "$work/ours-up.list" "$work/pub-up.txt" "$work/upstream.nv" "$work/pub-up.nv"
if [ "$rc" -eq 1 ] && grep -q '^identical to upstream, take it from upstream: lightdm-1.32.0_6$' "$work/stdout"; then
    ok "ours-check: a package identical to upstream fails"
else
    no "ours-check: a package identical to upstream fails" "rc=$rc: $(cat "$work/stdout")"
fi

# could not look: exit 2, never a pass
: > "$work/empty"
fixture comments-only '# nothing here' ''
for entry in 'an empty published list|ours.list empty' \
            'an empty ours.list|empty published.txt' \
            'a comments-only ours.list|comments-only published.txt' \
            'a missing published list|ours.list missing-file' \
            'an empty upstream name-version list|ours.list published.txt empty published.nv' \
            'an empty published name-version list|ours.list published.txt upstream.nv empty' \
            'one argument|ours.list' \
            'three arguments|ours.list published.txt upstream.nv'; do
    label=${entry%%|*}
    paths=
    for a in ${entry#*|}; do paths="$paths $work/$a"; done
    # shellcheck disable=SC2086
    Y sh "$ours" $paths
    if [ "$rc" -eq 2 ]; then ok "ours-check: $label is could-not-look (exit 2)"; else
        no "ours-check: $label is could-not-look (exit 2)" "rc=$rc: $(cat "$work/stdout")"; fi
done
Y sh "$ours" "$work/ours.list" "$work/missing-file"
if [ "$rc" -eq 2 ] && grep -q "^cannot read $work/missing-file: could not look " "$work/stdout"; then
    ok "ours-check: a file it cannot read is named in the could-not-look message"
else
    no "ours-check: a file it cannot read is named in the could-not-look message" "rc=$rc: $(cat "$work/stdout")"
fi

printf '\n'
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
