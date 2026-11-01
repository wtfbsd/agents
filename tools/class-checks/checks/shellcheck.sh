#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# The shellcheck class: every finding at warning level or above in every
# shell file (files without a shebang are read as POSIX sh), except the
# quoting codes unquoted-expansion reports, and "appears unused" (SC2034)
# for the rc.subr variables of an rc.d script. Without shellcheck it could
# not look (exit 2); setting CLASS_CHECKS_ALLOW_MISSING to "shellcheck"
# makes that a skip with a note.
. "$(dirname -- "$0")/../lib.sh"
cc_setup shellcheck "$@"
sc=${SHELLCHECK:-shellcheck}
cc_need_shellcheck "$sc"
cc_shellcheck "$sc" -S warning -e SC2086,SC2068,SC2048 > "$CC_WORK/sc.raw" ||
    cc_die "shellcheck failed; could not look"
# rc.subr reads rcvar, start_cmd, NAME_flags (FreeBSD/NetBSD/DragonFly) or
# daemon, daemon_flags, rc_bg, pexp (OpenBSD) and the like after the script
# sets them, so in an rc.d script shellcheck's "appears unused" for those is
# wrong; every other SC2034 stays
awk '
/\[SC2034\]$/ && $0 ~ /(^|\/)rc\.d\/[^\/:]+:[0-9]+:/ {
    v = $0
    sub(/^.*: warning: /, "", v)
    sub(/ appears unused.*$/, "", v)
    if (v ~ /^(name|rcvar|desc|command|command_args|command_interpreter|pidfile|procname|extra_commands|sig_stop|sig_reload|required_(dirs|files|modules|vars))$/ ||
        v ~ /^(daemon|daemon_[a-z]+|pexp|rc_bg|rc_reload|rc_reload_signal|rc_stop_signal|rc_usercheck|rc_exec)$/ ||
        v ~ /_(cmd|precmd|postcmd|chdir|chroot|nice|user|group|groups|env|env_file|flags|fib|limits|login_class|oomprotect|umask|svcj|svcj_options|program|enable)$/)
        next
}
{ print }' "$CC_WORK/sc.raw" > "$CC_WORK/sc.out" || cc_die "cannot filter the shellcheck output"
CC_SC_MSG='' cc_sc_hits "$CC_WORK/sc.out"
cc_finish
