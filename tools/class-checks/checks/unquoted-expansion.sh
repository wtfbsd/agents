#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# unquoted-expansion — unquoted $var, ${var}, $@ and $* in shell files,
# found by shellcheck (SC2086, SC2068, SC2048). Unquoted, a value is split on
# IFS and globbed, so a path with a space or a * becomes several arguments.
# Without shellcheck it could not look (exit 2); setting
# CLASS_CHECKS_ALLOW_MISSING to "shellcheck" makes that a skip with a note.
. "$(dirname -- "$0")/../lib.sh"
cc_setup unquoted-expansion "$@"
sc=${SHELLCHECK:-shellcheck}
cc_need_shellcheck "$sc"
cc_shellcheck "$sc" -i SC2086,SC2068,SC2048 > "$CC_WORK/sc.out" ||
    cc_die "shellcheck failed; could not look"
CC_SC_MSG='quote it ("$var", "$@"); for a list of words use set -- or a loop' \
    cc_sc_hits "$CC_WORK/sc.out"
cc_finish
