#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# apply-answers.sh — validate answers.yaml and emit product.conf.
#
# Input: the user's answers to the Q&A in AGENTS.md Phase 1 (see examples/)
# together with the questions.yaml contract. Output: a POSIX-sh sourceable
# product.conf with DISTRO_NAME, DISTRO_SLUG and every other answer key,
# after resolving defaults and enforcing the per-OS honesty rules.
#
# usage: scripts/apply-answers.sh [options] <answers.yaml>
#
#   -a, --answers FILE    answers file (same as the positional argument)
#   -q, --questions FILE  questions contract; default: questions.yaml
#                         beside this script
#   -o, --output FILE     where to write product.conf; default ./product.conf
#   -f, --force           overwrite an existing output file
#   -c, --check           validate and report only; write nothing
#   -h, --help            show this help
#
# Exit status: 0 answers valid, 2 usage error, 3 validation failure.
# Errors go to stderr; the validation report and warnings go to stdout.
#
# The parser here is deliberately tiny — see the "wtfbsd YAML subset" note
# at the top of questions.yaml. answers.yaml is a flat list of `KEY: value`
# lines; values must not contain "|", a backslash, an inner double quote or
# control characters (one outer pair of wrapping double quotes is allowed
# and is stripped).

set -eu

progname=$(basename -- "$0")

usage() {
    cat >&2 <<'HELP'
usage: apply-answers.sh [options] <answers.yaml>

  -a, --answers FILE    answers file (same as the positional argument)
  -q, --questions FILE  questions contract; default: questions.yaml beside
                        this script
  -o, --output FILE     where to write product.conf; default ./product.conf
  -f, --force           overwrite an existing output file
  -c, --check           validate and report only; write nothing
  -h, --help            show this help

Exit status: 0 answers valid, 2 usage error, 3 validation failure.
HELP
}

die() {
    printf '%s: error: %s\n' "$progname" "$1" >&2
    exit 3
}

die_usage() {
    printf '%s: %s\n' "$progname" "$1" >&2
    usage
    exit 2
}

warn() {
    printf '%s: warning: %s\n' "$progname" "$1"
}

# --------------------------------------------------------------- arguments
self_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
questions_file=$self_dir/../questions.yaml
answers_file=
output_file=product.conf
check_only=0
force=0

while [ $# -gt 0 ]; do
    case $1 in
        -a|--answers)   [ $# -ge 2 ] || die_usage "missing value for $1"
                        answers_file=$2; shift 2 ;;
        -q|--questions) [ $# -ge 2 ] || die_usage "missing value for $1"
                        questions_file=$2; shift 2 ;;
        -o|--output)    [ $# -ge 2 ] || die_usage "missing value for $1"
                        output_file=$2; shift 2 ;;
        -c|--check)     check_only=1; shift ;;
        -f|--force)     force=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        -*)             die_usage "unknown option $1" ;;
        *)              if [ -n "$answers_file" ]; then
                            die_usage "more than one answers file given"
                        fi
                        answers_file=$1; shift ;;
    esac
done
[ -n "$answers_file" ] || die_usage "no answers file given"

# filenames must never look like options to the tools invoked below
case $answers_file in   -*) answers_file=./$answers_file ;;   esac
case $questions_file in -*) die_usage "questions file must not start with '-'" ;; esac
case $output_file in    -*) output_file=./$output_file ;;     esac

[ -f "$answers_file" ]   || die_usage "answers file not found: $answers_file"
[ -f "$questions_file" ] || die_usage "questions file not found: $questions_file"

if [ "$check_only" -eq 0 ] && [ -e "$output_file" ] && [ "$force" -eq 0 ]; then
    printf '%s: refusing to overwrite %s without --force\n' \
        "$progname" "$output_file" >&2
    exit 2
fi

# scratch dir under TMPDIR (default /tmp)
tmp_prefix=${TMPDIR:-/tmp}
tmp_dir=$(mktemp -d "$tmp_prefix/wtfbsd-apply-answers.XXXXXX") || {
    printf '%s: error: cannot create a scratch directory\n' "$progname" >&2
    exit 3
}
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

# =====================================================================
# Parser: one small awk program serves both files. It emits records
# separated by tab characters:  kind<TAB>path<TAB>value  with kinds
#   q     <n>.<field>    one question field; field "id" names the answer
#                        key; items are numbered in file order
#   row   <n>.<col>      honest per_os rows (os, arch, root_fs, installer,
#                        zfs_pool)
#   dfo   <KEY>          default_from_os entries: answer key -> row column
#   ans   <KEY>          one answer line from answers.yaml
# =====================================================================
parser_file=$tmp_dir/parser.awk
cat > "$parser_file" <<'AWK'
# ------------------------------------------------------------- helpers
function fail(msg) {
    printf "%s\n", msg > "/dev/stderr"
    exit 1
}
function trim(s) {
    gsub(/^[ \t\r]+|[ \t\r]+$/, "", s)
    return s
}
# a value may not contain a backslash or inner quote; one outer pair of
# wrapping quotes is allowed and stripped here
function unwrap(s) {
    if (length(s) >= 2 && substr(s, 1, 1) == "\"" &&
        substr(s, length(s), 1) == "\"") {
        inner = substr(s, 2, length(s) - 2)
        if (index(inner, "\"") > 0)
            fail("only one pair of wrapping double quotes is allowed: " s)
        s = inner
    }
    return s
}
# values must not contain the separator, a backslash or control characters
function checkstr(s,    i, c) {
    if (s ~ /[\t\n\r]/) fail("values must not contain tab/newline: " s)
    for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c == "\"") fail("values must not contain a double quote: " s)
        if (c == "|")  fail("values must not contain the | separator: " s)
        if (c == "\\") fail("values must not contain a backslash: " s)
    }
    for (i = 1; i <= 127; i++) {
        c = sprintf("%c", i)
        if (i >= 32 && i < 127) continue
        if (index(s, c) > 0)
            fail("values must not contain control characters: " s)
    }
    return s
}
BEGIN { rowidx = 0; qidx = 0 }
# split str on commas NOT inside [ ... ]; returns pieces via the array
# parameter arr (arr["n"] holds the count) so callers never share state
function scanlist(str, arr,    i, c, depth, piece) {
    depth = 0; piece = ""
    arr["n"] = 0   # arrays persist between calls in awk — always reset
    for (i = 1; i <= length(str); i++) {
        c = substr(str, i, 1)
        if (c == "[") depth++
        if (c == "]") depth--
        if (c == "," && depth == 0) { addp(arr, piece); piece = "" }
        else piece = piece c
    }
    addp(arr, piece)
}
function addp(arr, p) {
    p = trim(p)
    if (p != "") arr[++arr["n"]] = p
}
# split "key: value" at the first colon
function split_kv(kv) {
    i = index(kv, ":")
    if (i == 0) fail("no colon in element: " kv)
    K = trim(substr(kv, 1, i - 1))
    V = trim(substr(kv, i + 1))
}
function emit(kind, path, v) { printf "%s\t%s\t%s\n", kind, path, v }
# a "[a, b, c]" field value becomes the record value a|b|c
function listjoin(inner,    v, j, ip) {
    v = ""
    scanlist(inner, ip)
    for (j = 1; j <= ip["n"]; j++) {
        if (v != "") v = v "|"
        v = v checkstr(ip[j])
    }
    return v
}

{
    line = $0
    if (line ~ /^[ \t\r]*$/ || line ~ /^[ \t\r]*#/) next

    # top-level section headers are bare `name:` lines at column 0
    if (line ~ /^[A-Za-z_][A-Za-z0-9_]*:[ \t]*$/) {
        section = line
        sub(/:[ \t]*$/, "", section)
        next
    }

    # ------------------------------------------------------- answers file
    if (srcmode == "answers") {
        if (line !~ /^[A-Za-z_][A-Za-z0-9_]*:[ \t]/)
            fail("answers file: not a flat `KEY: value` line: " line)
        split_kv(line)
        if (K ~ /[^A-Za-z0-9_]/) fail("answers file: bad key name: " K)
        emit("ans", K, checkstr(unwrap(V)))
        next
    }

    # ------------------------------------------------------------- per_os
    if (section == "per_os") {
        if (line ~ /^[ \t]*-[ \t]*\{/) {
            row = line
            sub(/^[ \t]*-[ \t]*\{/, "", row)
            sub(/\}[ \t\r]*$/, "", row)
            osval = ""
            scanlist(row, rp)
            if (rp["n"] == 0) fail("per_os row is empty")
            for (pi = 1; pi <= rp["n"]; pi++) {
                split_kv(rp[pi])
                if (V ~ /^\[/) {
                    v = listjoin(substr(V, 2, length(V) - 2))
                } else {
                    if (index(V, ",") > 0)
                        fail("per_os row values must be scalars or [..]: " V)
                    v = checkstr(unwrap(V))
                }
                if (K == "os") osval = v
                emit("row", rowidx "." K, v)
            }
            if (osval == "") fail("per_os row has no os column")
            rowidx++
            next
        }
        fail("expected a per_os row: - { os: <name>, ... }")
    }

    # ---------------------------------------------------------- questions
    if (section == "questions") {
        if (line ~ /^[ \t]*-[ \t]*id:[ \t]/) {
            row = line; sub(/^[ \t]*-[ \t]*/, "", row)
            scanlist(row, qp)
            if (qp["n"] != 1) fail("question item line must be `- id: KEY`")
            split_kv(qp[1])
            if (K ~ /[^A-Za-z0-9_]/) fail("bad question id: " K)
            qidx++; curq = K
            emit("q", qidx ".id", V)
            next
        }
        if (curq == "") fail("question field before any question item")
        i = index(line, ":")
        if (i < 1) fail("no colon in question field line: " line)
        K = trim(substr(line, 1, i - 1))
        V = trim(substr(line, i + 1))
        if (K ~ /[^A-Za-z0-9_]/) fail("bad question field name: " K)
        if (V ~ /^\[/) {
            v = listjoin(substr(V, 2, length(V) - 2))
        } else {
            if (V == "") fail("empty value for question field " K " of " curq)
            v = checkstr(unwrap(V))
        }
        emit("q", qidx "." K, v)
        next
    }

    # ----------------------------------------------------- default_from_os
    if (section == "default_from_os") {
        if (line !~ /^[ \t]*[A-Za-z_][A-Za-z0-9_]*:[ \t]/) next
        split_kv(line)
        if (K ~ /[^A-Za-z0-9_]/) fail("bad default_from_os key: " K)
        if (V ~ /[^a-z_]/) fail("default_from_os values are per_os column names: " V)
        emit("dfo", K, V)
        next
    }

    next   # every other section (version, honesty prose) is prose to this tool
}
AWK
[ -s "$parser_file" ] || die "internal: parser text is empty"

awk -f "$parser_file" -v srcmode=questions "$questions_file" \
    > "$tmp_dir/questions.pairs" 2>"$tmp_dir/q.err" \
    || die "cannot parse questions.yaml: $(cat "$tmp_dir/q.err")"
awk -f "$parser_file" -v srcmode=answers "$answers_file" \
    > "$tmp_dir/answers.pairs" 2>"$tmp_dir/a.err" \
    || die "cannot parse answers file: $(cat "$tmp_dir/a.err")"

# ------------------------------------------------------- load records in sh
tab=$(printf '\t')
NQ=0
ROW_IDXS=
QIDS=
ANSKEYS=

# questions contract
while IFS="$tab" read -r kind path value; do
    case $kind in
        q)
            idx=${path%%.*}; field=${path#*.}
            case $idx in *[!0-9]*) die "internal: bad question index" ;; esac
            case $field in
                id) NQ=$idx
                    QIDS="$QIDS $value" ;;
                *[!A-Za-z0-9_]*) die "internal: bad question field '$field'" ;;
            esac
            eval "Q_${idx}_${field}=\$value"
            ;;
        row)
            idx=${path%%.*}; field=${path#*.}
            case $idx in *[!0-9]*) die "internal: bad per_os row index" ;; esac
            case $field in
                os) ROW_IDXS="$ROW_IDXS $idx"
                    eval "ROW_${idx}_os=\$value" ;;
                *[!a-z_]*) die "internal: bad per_os column '$field'" ;;
            esac
            eval "ROW_${idx}_${field}=\$value"
            ;;
        dfo)
            case $path in
                *[!A-Za-z0-9_]*) die "internal: bad default_from_os key" ;;
            esac
            eval "DFO_${path}=\$value"
            ;;
        *) die "internal: unexpected record kind '$kind'" ;;
    esac
done < "$tmp_dir/questions.pairs"

# answers
while IFS="$tab" read -r kind path value; do
    case $kind in
        ans)
            case $path in
                *[!A-Za-z0-9_]*) die "answers file: bad key name: $path" ;;
            esac
            if eval "[ \"\${ANS_${path}+x}\" ]"; then
                die "answers file: duplicate key: $path"
            fi
            ANSKEYS="$ANSKEYS $path"
            eval "ANS_${path}=\$value"
            ;;
        *) die "internal: unexpected record kind '$kind' in answers" ;;
    esac
done < "$tmp_dir/answers.pairs"

[ -n "$NQ" ] || die "questions.yaml has no questions"
[ -n "$ROW_IDXS" ] || die "questions.yaml has no per_os rows"

# every per_os row must name all honesty columns
for r in $ROW_IDXS; do
    for c in os arch root_fs installer zfs_pool; do
        eval "[ \"\${ROW_${r}_${c}+x}\" ]" \
            || die "internal: per_os row $r is missing column $c"
    done
done
# answers must only use known question ids
for k in $ANSKEYS; do
    case " $QIDS " in
        *" $k "*) : ;;
        *) die "answers file: unknown key '$k' — see questions.yaml" ;;
    esac
done
# question ids must be unique
checkids=
for id in $QIDS; do
    case " $checkids " in
        *" $id "*) die "internal: duplicate question id '$id'" ;;
        *) checkids="$checkids $id" ;;
    esac
done

# ------------------------------------------------------------- accessors
qf()       { eval "printf '%s' \"\${Q_${1}_${2}-}\""; }
ans_of()   { eval "printf '%s' \"\${ANS_$1-}\""; }
have_ans() { eval "[ \"\${ANS_$1+x}\" ]"; }
val_of()   { eval "printf '%s' \"\${VAL_$1-}\""; }
have_val() { eval "[ \"\${VAL_$1+x}\" ]"; }
dfo_col()  { eval "printf '%s' \"\${DFO_$1-}\""; }
row_os()   { eval "printf '%s' \"\${ROW_${1}_os}\""; }
row_val()  { eval "printf '%s' \"\${ROW_${1}_${2}}\""; }
listsp()   { printf '%s' "$1" | tr '|' ' '; }

pattern_ok() {
    # pattern_ok <answer key id> <resolved value>; the anchored ERE comes
    # from the contract. Local vars named pq* so caller state is untouched.
    pqi=$(qindex_for "$1")
    if [ -z "$pqi" ]; then
        return 1
    fi
    pre=$(qf "$pqi" pattern)
    if [ -z "$pre" ]; then
        return 0
    fi
    pval=$2
    awk -v v="$pval" -v re="$pre" 'BEGIN { if (v !~ re) exit 2 }'
}

qindex_for() {
    # answer key id -> contract index; uses its own loop variable so the
    # resolve loop's counter is never touched
    qi=0
    while [ "$qi" -lt "$NQ" ]; do
        qi=$((qi + 1))
        if [ "$(qf "$qi" id)" = "$1" ]; then
            printf '%s' "$qi"
            return 0
        fi
    done
    return 1
}

# --------------------------------------------------------------- required
if [ -z "$(ans_of DISTRO_OS)" ]; then
    die "DISTRO_OS (Q1) has no answer and no default — ask the user (AGENTS.md Q1)"
fi
DISTRO_OS=$(ans_of DISTRO_OS)

ROWN=
for r in $ROW_IDXS; do
    if [ "$(row_os "$r")" = "$DISTRO_OS" ]; then
        ROWN=$r
        break
    fi
done
if [ -z "$ROWN" ]; then
    die "questions.yaml has no per_os row for OS '$DISTRO_OS' (allowed:$(for r in $ROW_IDXS; do printf ' %s' "$(row_os "$r")"; done))"
fi

# ------------------------------------------------------------ resolve loop
resolve_all() {
    n=0
    while [ "$n" -lt "$NQ" ]; do
        n=$((n + 1))
        qid=$(qf "$n" id)
        qnumber=$(qf "$n" number)
        qtype=$(qf "$n" type)
        qchoices=$(qf "$n" choices)
        qdefault=$(qf "$n" default)
        qreqif=$(qf "$n" required_if)

        # required_if "KEY=choice": resolve the gate BEFORE anything else so
        # a not-applicable key neither dies on a missing answer nor resolves
        if [ -n "$qreqif" ]; then
            case $qreqif in *=*) : ;; *) die "internal: bad required_if on $qid" ;; esac
            gk=${qreqif%%=*}
            gv=${qreqif#*=}
            if ! have_val "$gk"; then
                die "internal: required_if on $qid refers to unknown key $gk"
            fi
            if [ "$(val_of "$gk")" != "$gv" ]; then
                if have_ans "$qid"; then
                    warn "$qid answered but ignored: applies only when $gk=$gv"
                fi
                val=""
                src="not applicable ($gk is not $gv)"
                eval "VAL_${qid}=\"\$val\""
                eval "VERB_${qid}=\"\$src\""
                continue
            fi
        fi

        val=
        src=
        [ -n "$qnumber" ] || die "internal: question $qid has no number field"
        case $qnumber in *[!0-9]*) die "internal: bad number on $qid" ;; esac
        if have_ans "$qid"; then
            val=$(ans_of "$qid")
            src="answer"
        fi

        if [ -z "$val" ]; then
            # the per_os row (default_from_os) wins over a fixed default
            col=$(dfo_col "$qid")
            if [ -n "$col" ]; then
                colval=$(row_val "$ROWN" "$col")
                val=${colval%%|*}
                src="first of the $DISTRO_OS per_os row ($col: $(listsp "$colval"))"
            elif [ -n "$qdefault" ]; then
                val=$qdefault
                src="fixed default"
            else
                die "$qid has no answer and no default — ask the user (AGENTS.md Q$qnumber)"
            fi
        fi

        # every value is checked and cross-checked below
        case $qtype in
            choice)
                cs=$(listsp "$qchoices")
                if [ -z "$cs" ]; then
                    die "internal: choice question $qid has no choices"
                fi
                if [ -z "$val" ]; then
                    die "$qid is empty; allowed: $cs"
                fi
                case " $cs " in
                    *" $val "*) : ;;
                    *) die "$qid value '${val}' is not allowed; allowed: $cs" ;;
                esac
                ;;
            string) : ;;
            *) die "internal: unknown question type '$qtype' for $qid" ;;
        esac

        if ! pattern_ok "$qid" "$val"; then
            die "$qid value '${val}' does not match the required format $(qf "$(qindex_for "$qid")" pattern) (see questions.yaml)"
        fi

        # min/max value lengths (patterns avoid awk-unsupported intervals)
        qmin=$(qf "$n" min)
        qmax=$(qf "$n" max)
        vlen=${#val}
        if [ -n "$qmin" ] && [ "$vlen" -lt "$qmin" ]; then
            die "$qid value has $vlen characters; at least $qmin required"
        fi
        if [ -n "$qmax" ] && [ "$vlen" -gt "$qmax" ]; then
            die "$qid value has $vlen characters; at most $qmax allowed"
        fi

        eval "VAL_${qid}=\"\$val\""
        eval "VERB_${qid}=\"\$src\""
    done
}

# the loop runs in file order so required_if gates see earlier keys first
resolve_all

# ------------------------------------- per-OS honesty (the heart of Q&A)
archlist=$(listsp "$(row_val "$ROWN" arch)")
fslist=$(listsp "$(row_val "$ROWN" root_fs)")
inslist=$(listsp "$(row_val "$ROWN" installer)")
zsfpool=$(row_val "$ROWN" zfs_pool)

case " $archlist " in
    *" $(val_of DISTRO_ARCH) "*) : ;;
    *) die "DISTRO_ARCH=$(val_of DISTRO_ARCH) is not covered by the $DISTRO_OS row (allowed: $archlist)" ;;
esac
case " $fslist " in
    *" $(val_of FILESYSTEM_ROOT) "*) : ;;
    *) die "FILESYSTEM_ROOT=$(val_of FILESYSTEM_ROOT) is not a root filesystem on $DISTRO_OS (allowed: $fslist)" ;;
esac
case " $inslist " in
    *" $(val_of INSTALLER) "*) : ;;
    *) die "INSTALLER=$(val_of INSTALLER) is not available for $DISTRO_OS (allowed: $inslist)" ;;
esac

POOL_OK=no
if [ "$(val_of ZFS_DATA_POOL)" = "yes" ]; then
    case $zsfpool in
        yes)       POOL_OK=yes ;;
        data-only) POOL_OK=data-only ;;
        no)        die "ZFS_DATA_POOL=yes is not possible on $DISTRO_OS — that OS has no ZFS at all" ;;
        *)         die "internal: unknown zfs_pool row entry: $zsfpool" ;;
    esac
    if [ -z "$(val_of ZFS_POOL_NAME)" ]; then
        die "ZFS_DATA_POOL=yes needs a ZFS_POOL_NAME"
    fi
else
    if [ -n "$(val_of ZFS_POOL_NAME)" ]; then
        warn "ZFS_POOL_NAME answered but ZFS_DATA_POOL is '$(val_of ZFS_DATA_POOL)' — name ignored"
    fi
fi

if [ "$(val_of PACKAGE_SET)" = "base-desktop" ] && [ "$(val_of PROFILE)" = "appliance" ]; then
    warn "package set base-desktop with PROFILE=appliance — regenerate answers if unintended"
fi
if [ "$(val_of PACKAGE_SET)" = "base-server" ] && [ "$(val_of PROFILE)" = "desktop" ]; then
    warn "package set base-server with PROFILE=desktop — regenerate answers if unintended"
fi

# ------------------------------------------------------------------ report
printf '%s\n' "Answers are valid. product.conf keys for $(val_of DISTRO_NAME):"
printf '%s\n' "  (Q numbers refer to the numbered questions in AGENTS.md Phase 1)"
printf '  %-4s %-16s %-18s %s\n' "Q" "key" "value" "source"
n=0
while [ "$n" -lt "$NQ" ]; do
    n=$((n + 1))
    qid=$(qf "$n" id)
    qnumber=$(qf "$n" number)
    vsrc=$(eval "printf '%s' \"\${VERB_${qid}-}\"")
    printf '  %-4s %-16s %-18s %s\n' "Q$qnumber" "$qid" "$(val_of "$qid")" "$vsrc"
done
if [ "$POOL_OK" = "data-only" ]; then
    warn "on $DISTRO_OS ZFS pools are data-only; the root filesystem stays $(val_of FILESYSTEM_ROOT)"
fi

# ------------------------------------------------------- write product.conf
esc_val() {
    # single-quote safe: $ and ` stay literal when product.conf is sourced;
    # an embedded ' becomes '\'' (sed, not awk gsub: no unspecified escapes).
    # Values never contain a newline (the parser rejects control characters).
    printf '%s' "$1" | sed "s/'/'\\\\''/g"
}

if [ "$check_only" -eq 1 ]; then
    printf '%s\n' "answers valid (--check: wrote nothing)"
    exit 0
fi

conf_tmp=$tmp_dir/product.conf
{
    printf '# product.conf — generated by scripts/apply-answers.sh from %s\n' \
        "$(basename "$answers_file")"
    printf '# The contract is questions.yaml; the flow is AGENTS.md / docs/E2E.md.\n'
    printf '# POSIX sh sourceable. Regenerate instead of hand-editing.\n'
    printf '#\n'
    n=0
    while [ "$n" -lt "$NQ" ]; do
        n=$((n + 1))
        qid=$(qf "$n" id)
        v=$(val_of "$qid")
        esc=$(esc_val "$v")
        printf "%s='%s'\n" "$qid" "$esc"
        if [ "$qid" = "ZFS_POOL_NAME" ] && [ -z "$v" ]; then
            printf '# ZFS_POOL_NAME is empty because ZFS_DATA_POOL is not "yes"\n'
        fi
    done
    printf '#\n'
    printf '# honest per-OS row used for this build (from questions.yaml):\n'
    printf '#   DISTRO_OS  %s\n' "$DISTRO_OS"
    printf '#   arch       %s\n' "$archlist"
    printf '#   root_fs    %s\n' "$fslist"
    printf '#   installer  %s\n' "$inslist"
    printf '#   zfs_pool   %s\n' "$zsfpool"
} > "$conf_tmp" || die "cannot stage $output_file"

mv "$conf_tmp" "$output_file" || die "cannot write $output_file"

printf '%s\n' "wrote $output_file"
exit 0
