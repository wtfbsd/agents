#!/bin/sh
eval "$cmd"
eval $(ssh-agent)
if x; then eval "export $k=\$v"; fi
eval `cat f`
x=1; eval "y=$x"
