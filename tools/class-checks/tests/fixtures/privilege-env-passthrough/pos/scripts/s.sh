#!/bin/sh
sudo -E make install
printf 'permit keepenv %s\n' "$u" >> /etc/doas.conf
sudo --preserve-env=PATH id
