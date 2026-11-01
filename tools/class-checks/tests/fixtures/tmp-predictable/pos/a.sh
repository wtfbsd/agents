#!/bin/sh
t=$(mktemp)
d=$(mktemp -d)
f=$(mktemp /tmp/foo.XXX)
n=$(mktemp -u "${TMPDIR:-/tmp}/x.XXXXXXXX")
echo x > /tmp/build.log
log=/var/tmp/out.$$
cfg="${TMPDIR:-/tmp}/cfg.txt"
cp a "$TMPDIR/fixed"
STATE=${X_STATE:-/tmp/fake.state}
S=${Y:-/var/tmp/wtfbsd-vm}
