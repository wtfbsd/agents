#!/bin/sh
awk -v name="$1" 'BEGIN{print name}'
awk -F: -v home=$HOME '{print}' /etc/passwd
awk -vx="${val}" 'BEGIN{}'
nawk -v p="$(pwd)" 'BEGIN{}'
awk \
    -v k="$key" 'BEGIN{}'
