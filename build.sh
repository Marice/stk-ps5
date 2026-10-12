#!/usr/bin/env bash
# Builds SuperTuxKart for the PlayStation 5.
#
# Everything the game's own CMakeLists cannot know about this target lives in
# ps5-gl.cmake and ps5-pkg-config; stk-code itself is touched in two places
# only, to skip the DNS resolver this platform does not have.
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
: "${PS5_PAYLOAD_SDK:=/opt/ps5-payload-sdk}"
: "${PACBREW:=$HOME/development/workspace/trimui/olise-player/.deps/pacbrew/v0.40.2/sysroot/user/homebrew}"
export PS5_PAYLOAD_SDK PACBREW

[ -d "$PACBREW/lib" ] || { echo "PacBrew sysroot not found at $PACBREW" >&2; exit 1; }
[ -d "$root/stk-code" ] || { echo "stk-code is missing; clone it first" >&2; exit 1; }

cmake -B "$root/build-ps5" -S "$root/stk-code" \
    -DCMAKE_TOOLCHAIN_FILE="$PS5_PAYLOAD_SDK/toolchain/prospero.cmake" \
    -DCMAKE_PROJECT_INCLUDE_BEFORE="$root/ps5-gl.cmake" \
    -DPKG_CONFIG_EXECUTABLE="$root/ps5-pkg-config" \
    -DCMAKE_PREFIX_PATH="$PACBREW" \
    -DCMAKE_FIND_ROOT_PATH="$PACBREW" \
    -DNO_SHADERC=on \
    -DCHECK_ASSETS=off \
    -DUSE_SYSTEM_ENET=off \
    -DUSE_SYSTEM_MCPP=off \
    -DUSE_SQLITE3=off \
    -DBUILD_RECORDER=off \
    -DUSE_WIIUSE=off

cmake --build "$root/build-ps5" -j"$(nproc)"

# The ELF becomes a title binary in two steps: converted to the native layout
# against the console's module stubs, then signed as a fake SELF.
: "${PS5_NATIVE_TOOL:=$HOME/development/workspace/trimui/olise-player/build/host/ps5-native-tool}"
[ -x "$PS5_NATIVE_TOOL" ] || { echo "ps5-native-tool not found at $PS5_NATIVE_TOOL" >&2; exit 1; }
"$PS5_NATIVE_TOOL" link --in "$root/build-ps5/bin/supertuxkart" \
    --out "$root/pkg/eboot.elf" --stub-dir "$root/pkg/stubs" \
    --module-sdk 0x02000009 --companion-sdk 0x08050001 --file-name eboot.elf
"$PS5_NATIVE_TOOL" self --sign --in "$root/pkg/eboot.elf" \
    --out "$root/pkg/PPSA69421/eboot.bin" --magic 0x1D3D154F
ls -la "$root/pkg/PPSA69421/eboot.bin"

# param.json and the icon live in the repository (the catalog reads them from
# there); the title folder gets copies.
mkdir -p "$root/pkg/PPSA69421/sce_sys"
cp "$root/sce_sys/param.json" "$root/sce_sys/icon0.png" "$root/pkg/PPSA69421/sce_sys/"

# A title may not list a folder, so the listing of the asset tree is written
# down here and read back by ps5-posix.c: folder, name, d or f per line.
(cd "$root/pkg/PPSA69421" && find data -mindepth 1 -printf '%h\t%f\t%y\n' \
    | sed 's/\tl$/\tf/' | LC_ALL=C sort > dirs.txt)
wc -l "$root/pkg/PPSA69421/dirs.txt"
