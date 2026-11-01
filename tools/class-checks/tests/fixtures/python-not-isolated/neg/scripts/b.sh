#!/bin/sh
python3 -I -c 'print(1)'
python3 -Ic 'print(1)'
out=$(python3 -I tool.py)
command -v python3 >/dev/null
pkg install -y python3
echo "run python3 by hand"
# python3 -c 'commented out'
python3 --version
py=python3-config
die "need (python3 3.11)"
case $x in a) python3 -I x ;; esac
