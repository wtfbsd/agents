#!/bin/sh
curl -fsSLo i.sh https://example.org/i.sh
sha256 -c "$sum" i.sh && sh i.sh
curl -s https://example.org/x | grep foo
fetch -o - https://example.org/list | sha256
