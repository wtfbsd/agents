#!/bin/sh
t=$(mktemp "${TMPDIR:-/tmp}/x.XXXXXXXX")
d=$(mktemp -d -t wtfbsd)
TMPDIR=/tmp
cd /tmp
w=$(mktemp -d /tmp/wtfbsd.XXXXXX)
rm -rf "$w/tmp/foo"
# echo > /tmp/x
tmp_prefix=${TMPDIR:-/tmp}
w=$(mktemp -d "$tmp_prefix/x.XXXXXXXX")
die "mktemp failed (see python3 docs)"
warn "cannot mktemp -u here"
case $d in /tmp/wtfbsd-media.??????) : ;; esac
grep -q '/tmp/wtfbsd-media\.' log
rm -rf /tmp/wtfbsd-media.*
