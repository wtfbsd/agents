#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# run-tests.sh — tests for tools/class-checks.
#
# For every class there is a positive fixture tree (fixtures/CLASS/pos, which
# must produce exactly the hits listed in fixtures/CLASS/pos.expect) and a
# negative one (fixtures/CLASS/neg, which must produce none). Then run.sh is
# tested: allow-list matching, an entry without a reason, an unknown class, a
# stale entry, several repos, a missing directory, a missing shellcheck, and
# finally tools/class-checks itself, which must pass its own checks.
#
#   tools/class-checks/tests/run-tests.sh
#   CLASS_CHECKS_DIR=/path/to/other/copy tools/class-checks/tests/run-tests.sh
#       run the same tests against another copy (to show them red)

set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
cc=${CLASS_CHECKS_DIR:-$(dirname -- "$here")}
fixtures=$here/fixtures
agents=$(dirname -- "$(dirname -- "$here")")
agents=$(dirname -- "$agents")

[ $# -eq 0 ] || { printf 'usage: %s\n' "$0" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/class-checks-tests.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
trap 'rm -rf "$work"; exit 2' HUP INT TERM

pass=0
fail=0
ok() { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
no() {
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$1"
    shift
    for l in "$@"; do printf '%s\n' "$l" | sed 's/^/      /'; done
}

# Y CMD... — run, keep stdout/stderr in $work, status in rc
Y() {
    "$@" >"$work/out" 2>"$work/err" || { rc=$?; return 0; }
    rc=0
}

classes='python-not-isolated privilege-env-passthrough awk-v-variable
eval-nonliteral root-write-user-dir tmp-predictable pipe-to-shell
unquoted-expansion shellcheck'

have_sc=yes
command -v "${SHELLCHECK:-shellcheck}" >/dev/null 2>&1 || have_sc=no
# without shellcheck run.sh is could-not-look (exit 2); the run.sh tests
# below are about other things, so on such a host they opt in to the skip
if [ "$have_sc" = no ]; then
    CLASS_CHECKS_ALLOW_MISSING=shellcheck
    export CLASS_CHECKS_ALLOW_MISSING
fi

# nosc: a PATH with every command of this host except shellcheck
nosc=$work/nosc-bin
mkdir "$nosc"
for d in /usr/local/bin /usr/bin /bin; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
        n=${f##*/}
        [ "$n" != shellcheck ] && [ ! -e "$nosc/$n" ] && ln -s "$f" "$nosc/$n"
    done
done
# failawk: a PATH whose awk fails (exit 2) when it is given a class check's
# scanning program (lib.awk defines hit()), and is the real awk otherwise
failawk=$work/failawk-bin
mkdir "$failawk"
realawk=$(command -v awk)
cat > "$failawk/awk" <<EOF
#!/bin/sh
for a in "\$@"; do
    case \$a in *'function hit('*) echo 'awk: forced failure' >&2; exit 2 ;; esac
done
exec "$realawk" "\$@"
EOF
chmod +x "$failawk/awk"

for c in $classes; do
    case $c in unquoted-expansion|shellcheck)
        if [ "$have_sc" = no ]; then
            printf 'SKIP  %s: shellcheck is not installed\n' "$c"
            continue
        fi
    esac
    check=$cc/checks/$c.sh

    # positive: exit 1, every line names the class, hits == pos.expect
    Y sh "$check" "$fixtures/$c/pos"
    sed -n 's/^\([^:]*:[0-9][0-9]*\): .*/\1/p' "$work/out" | LC_ALL=C sort -u > "$work/got"
    LC_ALL=C sort -u "$fixtures/$c/pos.expect" > "$work/want"
    bad=$(grep -cv "^[^:]*:[0-9][0-9]*: $c: ." "$work/out" || :)
    if [ "$rc" -eq 1 ] && [ "$bad" -eq 0 ] && cmp -s "$work/got" "$work/want"; then
        ok "$c: positive fixture gives exactly the expected hits"
    else
        no "$c: positive fixture gives exactly the expected hits" \
            "rc=$rc malformed=$bad" \
            "diff want got: $(diff "$work/want" "$work/got" || :)" \
            "stderr: $(cat "$work/err")"
    fi

    # negative: exit 0, no output
    Y sh "$check" "$fixtures/$c/neg"
    if [ "$rc" -eq 0 ] && [ ! -s "$work/out" ]; then
        ok "$c: negative fixture is clean"
    else
        no "$c: negative fixture is clean" "rc=$rc" "$(cat "$work/out" "$work/err")"
    fi
done

# --- run.sh -----------------------------------------------------------------
run=$cc/run.sh

# a scratch repo with one known hit per line
repo=$work/repo
cp -R "$fixtures/run" "$repo"

Y sh "$run" "$repo"
if [ "$rc" -eq 1 ] && grep -q "^$repo/scripts/x.sh:2: eval-nonliteral: " "$work/out" &&
    grep -q "^$repo/scripts/x.sh:3: tmp-predictable: " "$work/out"; then
    ok "run.sh: hits are reported with the repo prefix and exit 1"
else
    no "run.sh: hits are reported with the repo prefix and exit 1" "rc=$rc" "$(cat "$work/out" "$work/err")"
fi

Y sh -c 'cd "$1" && sh "$2" .' sh "$repo" "$run"
if [ "$rc" -eq 1 ] && grep -q '^scripts/x.sh:2: eval-nonliteral: ' "$work/out"; then
    ok "run.sh: '.' prints paths relative to the repo"
else
    no "run.sh: '.' prints paths relative to the repo" "rc=$rc" "$(cat "$work/out" "$work/err")"
fi

cat > "$repo/.class-checks-allow" <<'EOF'
# class path:line reason
eval-nonliteral scripts/x.sh:2 the argument is the test harness's own fixed string
tmp-predictable scripts/*.sh:* scratch scripts only run by the test author
EOF
Y sh "$run" "$repo"
if [ "$rc" -eq 0 ] && ! grep -q ': eval-nonliteral: \|: tmp-predictable: ' "$work/out"; then
    ok "run.sh: allow-list entries (exact and glob) suppress their hits"
else
    no "run.sh: allow-list entries (exact and glob) suppress their hits" "rc=$rc" "$(cat "$work/out" "$work/err")"
fi

cat > "$repo/.class-checks-allow" <<'EOF'
eval-nonliteral scripts/x.sh:3 wrong line so this must not hide line 2
tmp-predictable scripts/x.sh:3 scratch scripts only run by the test author
EOF
Y sh "$run" "$repo"
if [ "$rc" -eq 1 ] && grep -q 'x.sh:2: eval-nonliteral: ' "$work/out" &&
    grep -q '\.class-checks-allow:1: stale' "$work/err"; then
    ok "run.sh: an entry for another line does not hide a hit and is reported stale"
else
    no "run.sh: an entry for another line does not hide a hit and is reported stale" "rc=$rc" "$(cat "$work/out" "$work/err")"
fi

printf 'eval-nonliteral scripts/x.sh:2\n' > "$repo/.class-checks-allow"
Y sh "$run" "$repo"
if [ "$rc" -eq 2 ] && grep -q '\.class-checks-allow:1: .*reason' "$work/err"; then
    ok "run.sh: an allow entry without a reason is an error (exit 2)"
else
    no "run.sh: an allow entry without a reason is an error (exit 2)" "rc=$rc" "$(cat "$work/out" "$work/err")"
fi

printf 'eval-nonliteral scripts/x.sh:2 ok\n' > "$repo/.class-checks-allow"
Y sh "$run" "$repo"
if [ "$rc" -eq 2 ] && grep -q '\.class-checks-allow:1: .*reason' "$work/err"; then
    ok "run.sh: a one-word reason is not a written reason (exit 2)"
else
    no "run.sh: a one-word reason is not a written reason (exit 2)" "rc=$rc" "$(cat "$work/out" "$work/err")"
fi

printf 'no-such-class scripts/x.sh:2 because I said so here\n' > "$repo/.class-checks-allow"
Y sh "$run" "$repo"
if [ "$rc" -eq 2 ] && grep -q '\.class-checks-allow:1: unknown class' "$work/err"; then
    ok "run.sh: an unknown class in the allow-list is an error (exit 2)"
else
    no "run.sh: an unknown class in the allow-list is an error (exit 2)" "rc=$rc" "$(cat "$work/out" "$work/err")"
fi

printf 'eval-nonliteral scripts/x.sh two words here\n' > "$repo/.class-checks-allow"
Y sh "$run" "$repo"
if [ "$rc" -eq 2 ] && grep -q '\.class-checks-allow:1: ' "$work/err"; then
    ok "run.sh: an entry without :line is an error (exit 2)"
else
    no "run.sh: an entry without :line is an error (exit 2)" "rc=$rc" "$(cat "$work/out" "$work/err")"
fi
rm -f "$repo/.class-checks-allow"

clean=$work/clean
mkdir -p "$clean"
printf '#!/bin/sh\nset -eu\nprintf "%%s\\n" hello\n' > "$clean/ok.sh"
Y sh "$run" "$clean" "$repo"
if [ "$rc" -eq 1 ] && grep -q "^$repo/scripts/x.sh:2: " "$work/out" && ! grep -q "^$clean/" "$work/out"; then
    ok "run.sh: several repos, a hit in any one fails the run"
else
    no "run.sh: several repos, a hit in any one fails the run" "rc=$rc" "$(cat "$work/out" "$work/err")"
fi

Y sh "$run" "$clean"
if [ "$rc" -eq 0 ]; then ok "run.sh: a clean repo passes"; else
    no "run.sh: a clean repo passes" "rc=$rc" "$(cat "$work/out" "$work/err")"; fi

Y sh "$run" "$work/does-not-exist"
if [ "$rc" -eq 2 ] && grep -q 'does-not-exist' "$work/err"; then
    ok "run.sh: a missing directory is could-not-look (exit 2)"; else
    no "run.sh: a missing directory is could-not-look (exit 2)" "rc=$rc"; fi

Y env -u CLASS_CHECKS_ALLOW_MISSING PATH="$nosc" sh "$run" "$clean"
if [ "$rc" -eq 2 ] && grep -q 'shellcheck: shellcheck is not installed' "$work/err" &&
    grep -q 'unquoted-expansion: shellcheck is not installed' "$work/err"; then
    ok "run.sh: a PATH without shellcheck is could-not-look (exit 2), naming both classes"
else
    no "run.sh: a PATH without shellcheck is could-not-look (exit 2), naming both classes" "rc=$rc" "$(cat "$work/err")"
fi

Y env CLASS_CHECKS_ALLOW_MISSING=shellcheck PATH="$nosc" sh "$run" "$clean"
if [ "$rc" -eq 0 ] && grep -q 'shellcheck is not installed.*skipped (CLASS_CHECKS_ALLOW_MISSING)' "$work/err"; then
    ok "run.sh: CLASS_CHECKS_ALLOW_MISSING=shellcheck turns that into a printed skip (exit 0)"
else
    no "run.sh: CLASS_CHECKS_ALLOW_MISSING=shellcheck turns that into a printed skip (exit 0)" "rc=$rc" "$(cat "$work/err")"
fi

Y env -u CLASS_CHECKS_ALLOW_MISSING PATH="$nosc" sh "$cc/checks/shellcheck.sh" "$clean"
if [ "$rc" -eq 2 ]; then ok "shellcheck check alone: shellcheck missing is exit 2"; else
    no "shellcheck check alone: shellcheck missing is exit 2" "rc=$rc" "$(cat "$work/err")"; fi

# a scan that fails is could-not-look, never "no hits"
Y env PATH="$failawk:$PATH" sh "$cc/checks/eval-nonliteral.sh" "$repo"
if [ "$rc" -eq 2 ] && grep -q 'eval-nonliteral' "$work/err" && [ ! -s "$work/out" ]; then
    ok "a check whose awk fails exits 2, naming its class"
else
    no "a check whose awk fails exits 2, naming its class" "rc=$rc" "$(cat "$work/out" "$work/err")"
fi

Y env PATH="$failawk:$PATH" sh "$run" "$clean"
if [ "$rc" -eq 2 ] && grep -q 'could not look' "$work/err"; then
    ok "run.sh: a check whose scan fails makes the run exit 2"
else
    no "run.sh: a check whose scan fails makes the run exit 2" "rc=$rc" "$(cat "$work/err")"
fi

# a file the index cannot read is could-not-look too
unread=$work/unread
mkdir -p "$unread"
printf '#!/bin/sh\neval "$1"\n' > "$unread/x.sh"
chmod 000 "$unread/x.sh"
if [ -r "$unread/x.sh" ]; then
    printf 'SKIP  run.sh: an unreadable file: running as a user who can read mode 000\n'
else
    Y sh "$run" "$unread"
    if [ "$rc" -eq 2 ]; then ok "run.sh: a file it cannot read is could-not-look (exit 2)"; else
        no "run.sh: a file it cannot read is could-not-look (exit 2)" "rc=$rc" "$(cat "$work/out" "$work/err")"; fi
fi
chmod 600 "$unread/x.sh"

# dogfood: tools/class-checks passes its own checks, under the agents
# allow-list (which holds the fixtures and the checks' own message text)
self=$work/self
mkdir -p "$self/tools"
cp -R "$cc" "$self/tools/class-checks"
cp "$agents/.class-checks-allow" "$self/.class-checks-allow"
Y sh "$run" "$self"
if [ "$rc" -eq 0 ] && ! grep -q stale "$work/err"; then
    ok "run.sh: tools/class-checks passes its own checks, with no stale allow entries"
else
    no "run.sh: tools/class-checks passes its own checks, with no stale allow entries" "rc=$rc" "$(cat "$work/out" "$work/err")"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
