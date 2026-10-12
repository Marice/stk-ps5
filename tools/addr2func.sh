#!/usr/bin/env bash
# Turns the stack addresses from a crash report in stk.log into function names.
#
# The log prints the runtime address of log_stack next to the addresses found
# on the stack. The difference to its address in the linked binary is the load
# offset; each address minus that offset is looked up in the symbol table.
#
# Usage: tools/addr2func.sh < stk.log
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
binary="$root/build-ps5/bin/supertuxkart"
nm=${NM:-/opt/ps5-payload-sdk/bin/llvm-nm}

script=$(cat <<'PY'
import bisect, re, subprocess, sys

binary, nm = sys.argv[1], sys.argv[2]
symbols = []
for line in subprocess.run([nm, "-C", "--defined-only", binary],
                           capture_output=True, text=True, check=True).stdout.splitlines():
    parts = line.split(" ", 2)
    if len(parts) == 3 and parts[1] in "tTwW":
        symbols.append((int(parts[0], 16), parts[2]))
symbols.sort()
addresses = [a for a, _ in symbols]
link_reference = next(a for a, n in symbols if n.startswith("log_stack"))

offset = None
for line in sys.stdin:
    m = re.search(r"reference log_stack=(?:0x)?([0-9a-f]+)", line)
    if m:
        offset = int(m.group(1), 16) - link_reference
        print(line.rstrip())
        continue
    if "fps over" in line:
        print(line.rstrip())
        continue
    m = re.search(r"stack\[(-?\d+)\] (?:0x)?([0-9a-f]+)", line)
    if m and offset is not None:
        address = int(m.group(2), 16) - offset
        i = bisect.bisect_right(addresses, address) - 1
        if 0 <= address <= addresses[-1] + 0x100000 and i >= 0:
            print(f"  stack[{m.group(1)}] {symbols[i][1]}+0x{address - symbols[i][0]:x}")
        else:
            print(f"  stack[{m.group(1)}] {m.group(2)} (outside the game: a system module)")
        continue
    m = re.search(r"^(stk: (?:pipe|socketpair|socket).*caller )(?:0x)?([0-9a-f]+)", line)
    if m:
        r = re.search(r"reference log_stack=(?:0x)?([0-9a-f]+)", line)
        if r:
            offset = int(r.group(1), 16) - link_reference
        address = int(m.group(2), 16) - offset
        i = bisect.bisect_right(addresses, address) - 1
        print(f"{m.group(1)}{symbols[i][1]}+0x{address - symbols[i][0]:x}")
        continue
    m = re.search(r"(stk:   wait .*caller )(?:0x)?([0-9a-f]+)", line)
    if m and offset is not None:
        address = int(m.group(2), 16) - offset
        i = bisect.bisect_right(addresses, address) - 1
        name = symbols[i][1] if i >= 0 else "?"
        print(f"{m.group(1)}{name}+0x{address - symbols[i][0]:x}")
        continue
    if line.startswith(("klog:", "stk: assertion", "stk: main thread waited",
                        "stk:   context", "stk:     ", "stk:   no stack", "stk:   rip")):
        print(line.rstrip())
PY
)
python3 -I -c "$script" "$binary" "$nm"
