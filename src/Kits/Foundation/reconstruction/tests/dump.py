"""Print the reference disassembly for functions whose name matches a prefix.

Usage: dump.py [--analysis PATH] PREFIX [PREFIX ...]
"""

import json
import sys

ANALYSIS = "tools/binrecon/out/foundation-i386/published/analysis-reference-ida.json"

args = sys.argv[1:]
analysis_path = ANALYSIS
if args and args[0] == "--analysis":
    analysis_path = args[1]
    args = args[2:]

prefixes = tuple(args)
document = json.load(open(analysis_path))
for function in sorted(document["functions"], key=lambda f: f["address"]):
    names = function["names"]
    if not any(name.startswith(prefixes) for name in names):
        continue
    print("=" * 70)
    print(f"{', '.join(names)}  @ {function['address']:#x}  {function['size']} bytes")
    for instruction in function["instructions"]:
        print(f"  {instruction['address']:#010x}  "
              f"{instruction['mnemonic']:<8} {instruction['operands']}")
