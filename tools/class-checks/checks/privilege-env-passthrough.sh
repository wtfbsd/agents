#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# privilege-env-passthrough — doas/sudo rules that hand the caller's
# environment (PATH, LD_*, PYTHON*, ...) to the target user: doas keepenv or
# setenv, sudo !env_reset, SETENV, setenv, env_keep of a dangerous variable,
# and sudo -E / --preserve-env. Scans every text file, prose included: a
# guide that tells people to write "permit keepenv" ships the bug too.
. "$(dirname -- "$0")/../lib.sh"
cc_setup privilege-env-passthrough "$@"
cc_awk text <<'EOF'
/^[ \t]*#/ { next }
/(^|[^A-Za-z0-9_])permit([ \t]+(nopass|nolog|persist))*[ \t]+(keepenv|setenv)([ \t{]|$)/ {
    hit("doas rule passes the caller's environment to the target: drop keepenv/setenv and pass values as arguments"); next
}
/Defaults[^#]*!env_reset/ {
    hit("sudo !env_reset passes the caller's environment to root: keep env_reset (the default)"); next
}
/Defaults[^#]*env_keep[ \t]*[+]?=.*(PATH|LD_|PYTHON|PERL|RUBY|HOME|TMPDIR|BASH_ENV|IFS|SHELL|\*)/ {
    hit("sudo env_keep of a variable that changes what root runs: remove it and pass the value as an argument"); next
}
/(^|[ \t,(:=])SETENV[ \t]*:/ || /Defaults[^#]*[ \t,]setenv([ \t,]|$)/ {
    hit("sudo SETENV/setenv lets the caller set root's environment: remove it"); next
}
/(^|[^A-Za-z0-9_])sudo[ \t]+(-[A-Za-z]*E|--preserve-env)/ {
    hit("sudo told to preserve the environment hands it to root: drop -E / --preserve-env and pass needed values as arguments"); next
}
EOF
cc_finish
