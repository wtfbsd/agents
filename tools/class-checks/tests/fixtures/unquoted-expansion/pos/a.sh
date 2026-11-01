#!/bin/sh
f=$1
rm -f $f
set -- $@
echo $*
