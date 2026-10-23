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

set -eu

progname=$(basename "$0")
here=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
repo=$(dirname "$here")
apply="$repo/scripts/apply-answers.sh"
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

printf '\n'
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
