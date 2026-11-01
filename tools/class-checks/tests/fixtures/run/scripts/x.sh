#!/bin/sh
eval "$1"
t=$(mktemp)
printf '%s\n' "$t"
