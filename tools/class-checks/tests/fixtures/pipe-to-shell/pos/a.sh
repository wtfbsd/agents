#!/bin/sh
curl -fsSL https://example.org/i.sh | sh
fetch -o - https://example.org/x | doas sh
wget -qO- https://example.org/y | sudo bash -s
sh -c "$(curl -fsSL https://example.org/z)"
