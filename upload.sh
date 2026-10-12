#!/usr/bin/env bash
# Copies the packaged title to the console over FTP.
#
# 810 MB over FTP takes a while; the asset tree is the bulk of it and only has
# to go once. Re-running skips nothing, so pass --eboot to send just the binary
# after a rebuild.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
: "${PS5_HOST:=192.168.68.125}"
: "${PS5_PORT:=1337}"
title=PPSA69421
src="$root/pkg/$title"
dest="ftp://$PS5_HOST:$PS5_PORT/data/homebrew/$title"

[ -f "$src/eboot.bin" ] || { echo "nothing packaged yet; run build.sh first" >&2; exit 1; }

# Percent-encodes each path segment: the asset tree holds names with spaces
# and curl reads those as a malformed URL. -g keeps it from treating square
# brackets as a globbing range.
encode() {
    python3 -c 'import sys, urllib.parse; print("/".join(urllib.parse.quote(p, safe="") for p in sys.argv[1].split("/")))' "$1"
}

send() {  # send <relative path>
    curl -sS -f -g --max-time 900 --ftp-create-dirs -T "$src/$1" "$dest/$(encode "$1")"
}

if [ "${1:-}" = "--eboot" ]; then
    send eboot.bin
    echo "eboot.bin sent"
    exit 0
fi

count=0
while IFS= read -r file; do
    rel=${file#"$src/"}
    if send "$rel"; then
        count=$((count + 1))
        [ $((count % 250)) -eq 0 ] && printf '  %d files\n' "$count"
    else
        echo "failed: $rel" >&2
    fi
done < <(find "$src" -type f | sort)
printf 'sent %d files\n' "$count"
