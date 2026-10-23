#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# fork-distro.sh — fork the wtfbsd template repositories for a new
# distribution and rename the forks into place.
#
# Dry-run is the default: it prints the plan and the exact gh commands and
# performs no network action. With --apply it forks:
#
#     wtfbsd/<os>-template      -> <org>/<slug>            (product repo)
#     wtfbsd/ports-templates    -> <org>/<slug>-ports
#     wtfbsd/installer-template -> <org>/<slug>-installer
#     wtfbsd/ci-templates       -> <org>/<slug>-ci
#
# and sets each fork's description. Cloning, apply-answers.sh and the rest
# of the flow belong to the agent — see AGENTS.md Phase 2.
#
# usage: scripts/fork-distro.sh --os <os> --name <Name> --slug <slug> \
#                    --org <github-org> [--template-org <org>] [--apply]
#
#   --os <os>             which base OS template to fork (freebsd, netbsd,
#                         openbsd, dragonfly or illumos)
#   --name <Name>         human-facing distribution name (e.g. ExampleBSD)
#   --slug <slug>         lowercase slug for repo and file names
#   --org <org>           GitHub org or account the forks are created in
#   --template-org <org>  org that owns the templates (default wtfbsd)
#   --apply               actually fork; default is plan-only
#   -h, --help            show this help
#
# Exit status: 0 success (or clean dry-run), 2 usage error, 3 gh or
# preflight failure.

set -eu

progname=$(basename "$0")

usage() {
    cat >&2 <<'HELP'
usage: fork-distro.sh --os <os> --name <Name> --slug <slug> --org <github-org>
                      [--template-org <org>] [--apply]

  --os <os>             which base OS template to fork (freebsd, netbsd,
                        openbsd, dragonfly or illumos)
  --name <Name>         human-facing distribution name (e.g. ExampleBSD)
  --slug <slug>         lowercase slug for repo and file names
  --org <org>           GitHub org or account the forks are created in
  --template-org <org>  org that owns the templates (default wtfbsd)
  --apply               actually fork; default is plan-only
  -h, --help            show this help

Dry-run is the default: nothing touches the network until --apply is given.
Exit status: 0 success, 2 usage error, 3 gh or preflight failure.
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
os=
name=
slug=
org=
template_org=wtfbsd
apply=0

while [ $# -gt 0 ]; do
    case $1 in
        --os)            [ $# -ge 2 ] || die_usage "missing value for $1"
                         os=$2; shift 2 ;;
        --name)          [ $# -ge 2 ] || die_usage "missing value for $1"
                         name=$2; shift 2 ;;
        --slug)          [ $# -ge 2 ] || die_usage "missing value for $1"
                         slug=$2; shift 2 ;;
        --org)           [ $# -ge 2 ] || die_usage "missing value for $1"
                         org=$2; shift 2 ;;
        --template-org)  [ $# -ge 2 ] || die_usage "missing value for $1"
                         template_org=$2; shift 2 ;;
        --apply)         apply=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        -*)              die_usage "unknown option $1" ;;
        *)               die_usage "unexpected argument '$1' (flags only)" ;;
    esac
done
[ -n "$os" ]   || die_usage "--os is required"
[ -n "$name" ] || die_usage "--name is required"
[ -n "$slug" ] || die_usage "--slug is required"
[ -n "$org" ]  || die_usage "--org is required"

repo_root=$(CDPATH= cd "$(dirname "$0")/.." && pwd -P)
questions_file=$repo_root/questions.yaml
if [ -f "$questions_file" ] && [ -n "$(command -v awk 2>/dev/null)" ]; then
    os_list=$(awk '
        /^[A-Za-z_][A-Za-z0-9_]*:[ \t]*$/ { section = $0;
                                            sub(/:[ \t]*$/, "", section) }
        section == "per_os" && /^[ \t]*-[ \t]*\{/ {
            line = $0
            sub(/^[ \t]*-[ \t]*\{[ \t]*os:[ \t]*/, "", line)
            sub(/[ \t]*[,}].*$/, "", line)
            print line
        }' "$questions_file" | tr '\n' ' ')
else
    # contract not readable here: fall back to the five known systems
    os_list="freebsd netbsd openbsd dragonfly illumos"
fi

case " $os_list " in
    *" $os "*) : ;;
    *) die_usage "--os '$os' is not one of:$(printf '%s' "$os_list" \
       | tr ' ' '\n' | sed 's/^/ /' | tr -d '\n')" ;;
esac

name_len=${#name}
[ "$name_len" -ge 1 ] && [ "$name_len" -le 64 ] \
    || die "the name must be 1..64 characters"
case $name in
    *[[:cntrl:]]*|*'"'*|*"'"*|*'$'*|*'`'*|*'\\'*) die "the name must not contain quotes, \$, backquotes, backslashes or control characters" ;;
esac

for o in "$org" "$template_org"; do
    case $o in
        [A-Za-z0-9]*) : ;;
        *) die "org '$o' must start with a letter or digit" ;;
    esac
    case $o in
        *[!A-Za-z0-9-]*) die "org '$o' may contain only letters, digits and hyphens" ;;
    esac
    [ "${#o}" -le 39 ] || die "org '$o' is longer than 39 characters"
done

slug_len=${#slug}
case $slug in
    *[!a-z0-9-]*|''|'$') die "the slug must contain only lowercase letters, digits and hyphens" ;;
    [a-z]*) : ;;
    *) die "the slug must start with a lowercase letter" ;;
esac
[ "$slug_len" -ge 2 ] && [ "$slug_len" -le 32 ] \
    || die "the slug must be 2..32 characters"

case $slug in
    ports|installer|ci|agents|docs|template|templates)
        warn "slug '$slug' collides with template vocabulary; expect confusion" ;;
    ${template_org}) warn "slug equals the template org name" ;;
esac

product_repo=$slug
ports_repo=$slug-ports
installer_repo=$slug-installer
ci_repo=$slug-ci

src_product=$template_org/$os-template
src_ports=$template_org/ports-templates
src_installer=$template_org/installer-template
src_ci=$template_org/ci-templates

desc_product="$name — a $os-based distribution built from the wtfbsd templates"
desc_ports="$name ports overlay"
desc_installer="$name installer"
desc_ci="$name CI (Jenkins pipelines and throwaway build VMs)"

# gh command used for every fork: the template's default branch only
fork_cmd() {  # <src> <fork-name> <org>
    printf 'gh repo fork %s --fork-name %s --org %s --default-branch-only\n' \
        "$1" "$2" "$3"
}

# ---------------------------------------------------------------- the plan
plan_header() {
    printf '%s\n' "Fork plan for $name ($slug) on $os"
    printf '%s\n' "  template org:  $template_org"
    printf '%s\n' "  target org:    $org"
    printf '%s\n' "  product repo:  $org/$product_repo  (forked from $src_product)"
    printf '%s\n' "  ports repo:    $org/$ports_repo    (forked from $src_ports)"
    printf '%s\n' "  installer:     $org/$installer_repo (forked from $src_installer)"
    printf '%s\n' "  CI repo:       $org/$ci_repo        (forked from $src_ci)"
    printf '%s\n' ""
}

plan_body() {
    printf '%s\n' "  1. $(fork_cmd "$src_product" "$product_repo" "$org")"
    printf '%s\n' "  2. $(fork_cmd "$src_ports" "$ports_repo" "$org")"
    printf '%s\n' "  3. $(fork_cmd "$src_installer" "$installer_repo" "$org")"
    printf '%s\n' "  4. $(fork_cmd "$src_ci" "$ci_repo" "$org")"
}

plan_footer() {
    printf '%s\n' "  then rename descriptions:"
    printf '%s\n' "    gh repo edit $org/$product_repo --description '$desc_product'"
    printf '%s\n' "    gh repo edit $org/$ports_repo --description '$desc_ports'"
    printf '%s\n' "    gh repo edit $org/$installer_repo --description '$desc_installer'"
    printf '%s\n' "    gh repo edit $org/$ci_repo --description '$desc_ci'"
    printf '%s\n' ""
    printf '%s\n' "  next steps (agent work, see AGENTS.md):"
    printf '%s\n' "    1. clone the four repos into the product repo layout"
    printf '%s\n' "    2. scripts/apply-answers.sh answers.yaml -> product.conf"
    printf '%s\n' "    3. Jenkins build in a throwaway bhyve VM"
    printf '%s\n' "    4. installer E2E in bhyve, collect artifacts, publish"
}

if [ "$apply" -eq 0 ]; then
    plan_header
    plan_body
    plan_footer
    printf '%s\n' "dry run only; pass --apply to perform the forks"
    exit 0
fi

# ------------------------------------------------------------------ apply
command -v gh >/dev/null 2>&1 || die "gh not found in PATH — the GitHub CLI is required for --apply"

gh auth status >/dev/null 2>&1 || die "gh is not authenticated; run 'gh auth login' first"

plan_header
plan_body
plan_footer

gh_ok() {  # <args...> — expectation: exit 0
    gh "$@" >/dev/null 2>&1
}

# the fork target must not exist yet
for tgt in "$product_repo" "$ports_repo" "$installer_repo" "$ci_repo"; do
    if gh_ok repo view "$org/$tgt" 2>/dev/null; then
        die "refusing to continue: $org/$tgt already exists"
    fi
done

do_fork() {  # <src> <fork-name> <description>
    _src=$1; _tname=$2; _desc=$3
    printf 'forking %s -> %s/%s ... ' "$_src" "$org" "$_tname"
    if ! gh repo fork "$_src" --fork-name "$_tname" --org "$org" \
            --default-branch-only </dev/null; then
        printf 'failed\n'
        warn "gh repo fork failed for $_src — inspect gh output above"
        return 1
    fi
    printf 'done\n'
    printf 'setting description for %s/%s ... ' "$org" "$_tname"
    if ! gh repo edit "$org/$_tname" --description "$_desc" </dev/null; then
        printf 'failed (fork exists; set the description by hand later)\n'
        return 1
    fi
    printf 'done\n'
}

# continue on error so every fork is attempted; do_fork's progress lines
# show which succeeded, and the script exits non-zero if any failed
ret=0
do_fork "$src_product" "$product_repo" "$desc_product" || ret=$?
do_fork "$src_ports" "$ports_repo" "$desc_ports" || ret=$?
do_fork "$src_installer" "$installer_repo" "$desc_installer" || ret=$?
do_fork "$src_ci" "$ci_repo" "$desc_ci" || ret=$?

printf '%s\n' "fork phase finished: $product_repo, $ports_repo, $installer_repo, $ci_repo in $org"
if [ "$ret" -ne 0 ]; then
    warn "one or more post-fork steps failed; re-run --apply after fixing (existing forks are refused without cleanup)"
    exit 3
fi
printf '%s\n' ""
printf '%s\n' "Next: clone the forks and run scripts/apply-answers.sh as described in the plan above."
exit 0
