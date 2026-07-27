"""Classify every function IDA found into exactly one bucket.

Usage: bucket_functions.py <analysis.json> <source-map.json>

Buckets follow spec section 3.4. Buckets 1 and 2 are expected to be empty for
a _reloc kernel server: it is statically linked, not an MH_EXECUTE helper, so
it carries no crt/dyld routines and no __picsymbol_stub section.
"""
import json
import sys

CRT = {
    "start", "__start", "__call_mod_init_funcs", "__dyld_init_check",
    "dyld_stub_binding_helper", "__dyld_func_lookup",
}

analysis = json.load(open(sys.argv[1]))
smap = json.load(open(sys.argv[2]))

stub_ranges = [
    (s["address"], s["address"] + s["size"])
    for s in analysis["sections"]
    if s.get("name") == "__picsymbol_stub"
]

mapped = {e["address"] for e in smap["mapped"]}
unmapped = {e["address"] for e in smap["unmapped"]}

buckets = {
    "mapped": [],
    "1-crt-dyld": [],
    "2-picsymbol-stub": [],
    "3-unnamed-jump-island": [],
    "4-build-generated-class": [],
    "5-fn-with-source-site": [],
    "6-fn-no-source-site": [],
}

for fn in analysis["functions"]:
    addr = fn["address"]
    names = fn.get("names") or []
    first = names[0] if names else None

    if addr in mapped:
        buckets["mapped"].append((addr, first, fn["size"]))
    elif first in CRT:
        buckets["1-crt-dyld"].append((addr, first, fn["size"]))
    elif any(lo <= addr < hi for lo, hi in stub_ranges):
        buckets["2-picsymbol-stub"].append((addr, first, fn["size"]))
    elif not names:
        buckets["3-unnamed-jump-island"].append((addr, first, fn["size"]))
    elif "KernelServerInstance" in first or "Version driverKitVersion" in first:
        buckets["4-build-generated-class"].append((addr, first, fn["size"]))
    else:
        # Named, not glue, not placed by the map. Two cases land here: an
        # Objective-C method the map could not place, and a C function outside
        # --scope-to-objc entirely. Both need a manual source lookup, so the
        # script emits them together for triage and the operator moves any
        # confirmed match into bucket 5 with its file and line. Bucket 5 is
        # therefore always 0 straight out of the script.
        buckets["6-fn-no-source-site"].append((addr, first, fn["size"]))

total = len(analysis["functions"])
counted = sum(len(v) for v in buckets.values())

print(f"total functions: {total}")
for name, entries in buckets.items():
    print(f"  {name}: {len(entries)}")
    for addr, nm, size in entries:
        if not name.startswith(("mapped", "3-")):
            print(f"      0x{addr:x}  {nm}  ({size} bytes)")
print(f"counted: {counted}")
print(f"RECONCILES: {'yes' if counted == total else 'no'}")
