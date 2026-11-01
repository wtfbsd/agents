#!/bin/sh
python3 -c 'print(1)'
out=$(python3 tool.py)
if true; then python3.11 -m venv x; fi
doas /usr/local/bin/python3 setup.py
FOO=1 python -c pass
python3 - <<PY
PY
case $x in a) python3 x ;; esac
