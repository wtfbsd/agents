#!/bin/sh
awk -v n=3 'BEGIN{print n}'
awk -v sep='$' 'BEGIN{}'
NAME=$1 awk 'BEGIN{print ENVIRON["NAME"]}'
echo "-v x=$y"
# awk -v x="$y"
