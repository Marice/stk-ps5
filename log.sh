#!/usr/bin/env bash
# Reads the game's log back off the console.
#
# A native title has nowhere for stderr to go, so the build redirects it to
# stk.log in the title folder. That file is the only way to see how far the
# game got before it stopped.
set -euo pipefail

: "${PS5_HOST:=192.168.68.125}"
: "${PS5_PORT:=1337}"
title=PPSA69421

for dir in "/data/homebrew/$title" "/system_ex/app/$title"; do
    if curl -sS -f -g --max-time 60 "ftp://$PS5_HOST:$PS5_PORT$dir/stk.log" 2>/dev/null; then
        exit 0
    fi
done

echo "no stk.log found; the game may not have started at all" >&2
echo "ShadowMountPlus logs the launch itself:" >&2
curl -sS -f --max-time 30 "ftp://$PS5_HOST:$PS5_PORT/data/shadowmount/debug.log" 2>/dev/null \
    | grep "$title" | tail -12 || true
