#!/usr/bin/env bash
# Builds the release archive: dist/PPSA69421.zip with the PPSA69421/ title
# folder at its top, as the homebrew catalog and ProsperoStore expect. It holds
# the signed eboot.bin, sce_sys/, the libc runtime, the folder manifest and the
# complete asset tree; nothing the console writes (stk.log, .config/, .cache/,
# .local/) is ever part of pkg/, so nothing personal can end up in it.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
title=PPSA69421
app="$root/pkg/$title"

for need in eboot.bin sce_sys/param.json sce_sys/icon0.png sce_module/libc.prx dirs.txt data/stk_config.xml; do
    [ -e "$app/$need" ] || { echo "missing $app/$need; run build.sh first" >&2; exit 1; }
done

mkdir -p "$root/dist"
python3 -I - "$root/pkg" "$title" "$root/dist/$title.zip" <<'PY'
import os, sys, zipfile
base, title, out = sys.argv[1], sys.argv[2], sys.argv[3]
skip = {"stk.log", ".config", ".cache", ".local"}
count = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as z:
    for folder, dirs, files in os.walk(os.path.join(base, title)):
        dirs[:] = sorted(d for d in dirs if d not in skip)
        for name in sorted(files):
            if name in skip:
                continue
            path = os.path.join(folder, name)
            info = zipfile.ZipInfo.from_file(path, os.path.relpath(path, base))
            info.external_attr = 0o100777 << 16   # stored as 0777, as the catalog asks
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(path, "rb") as src:
                z.writestr(info, src.read(), compresslevel=6)
            count += 1
print(f"{out}: {count} files")
PY
(cd "$root/dist" && sha256sum "$title.zip" | tee "$title.zip.sha256")
