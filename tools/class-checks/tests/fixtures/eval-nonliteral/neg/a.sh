#!/bin/sh
eval 'set -- a b'
eval "set -- a b"
printf 'eval "$x"\n'
evaluate_thing "$x"
x=retrieval; echo "$x"
# eval "$x"
