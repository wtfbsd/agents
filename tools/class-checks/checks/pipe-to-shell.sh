#!/bin/sh
# Copyright (c) 2026 The wtfbsd contributors. BSD-2-Clause (see LICENSE).
#
# pipe-to-shell — a download fed straight to an interpreter: curl/fetch/wget/
# ftp ... | sh (or bash, python, perl, under doas/sudo too), sh -c "$(curl
# ...)", bash <(curl ...). Whatever the server (or anyone between) sends
# runs. Scans every text file, prose included: install guides are where this
# lives.
. "$(dirname -- "$0")/../lib.sh"
cc_setup pipe-to-shell "$@"
cc_awk text <<'EOF'
FILENAME !~ /\.(md|markdown|txt|rst|html?)$/ && /^[ \t]*#/ { next }
/(^|[^A-Za-z0-9_.-])(curl|fetch|wget|ftp)([ \t][^|]*)?\|[ \t]*((doas|sudo)([ \t]+-[^ \t]+)*[ \t]+)?(env[ \t]+)?([^ \t|]*\/)?(sh|bash|ksh|mksh|dash|ash|zsh|python[0-9.]*|perl|ruby)([ \t"')]|$)/ ||
/(^|[^A-Za-z0-9_.-])(sh|bash|ksh|mksh|zsh)[ \t]+-c[ \t]+["']?\$\([ \t]*(curl|fetch|wget|ftp)[ \t]/ ||
/(^|[^A-Za-z0-9_.-])(sh|bash|ksh|mksh|zsh)[ \t]+<\([ \t]*(curl|fetch|wget|ftp)[ \t]/ {
    hit("a download piped into a shell runs whatever arrives: download to a file, verify its checksum or signature, then run it")
}
EOF
cc_finish
