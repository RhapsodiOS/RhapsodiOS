#!/usr/bin/env python3
"""Generate exact CRTC and IODisplayInfo declarations from the sealed contract."""
from __future__ import annotations
import json
import argparse
import hashlib
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
CONTRACT = Path(__file__).with_name("reference-contract.json")
OUTPUT = Path(__file__).parents[2] / "ATIRageDisplayDriver.drvproj" / "ATIRageDisplayDriver.lksproj" / "ATIRageModes.h"

def u32(data: bytes, off: int) -> int:
    return struct.unpack_from("<I", data, off)[0]

def s32(data: bytes, off: int) -> int:
    return struct.unpack_from("<i", data, off)[0]

def emit(check: bool = False, resource_root: Path | None = None) -> None:
    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    modes = contract["display_modes"]["records"]
    crtcs = contract["crtc_timings"]["records"]
    auxiliary = contract["auxiliary_data"]
    tables = {item["name"]: item for item in auxiliary["tables"]}
    assert len(modes) == 72 and len(crtcs) == 18
    out = ["/* Generated from reference-contract.json; do not hand-edit table records. */",
           "#ifndef __ATIRAGE_MODES_H__", "#define __ATIRAGE_MODES_H__", "",
           '#import "ATI_BIOS.h"', '#import <driverkit/driverTypes.h>', "",
           ]
    vga_crtc = bytes.fromhex(crtcs[0]["bytes_hex"])
    assert len(vga_crtc) == 30
    out.append("static const unsigned char AtiVgaCRTC[30] = {")
    out.append("    " + ", ".join(f"0x{b:02x}" for b in vga_crtc))
    out += ["};", ""]
    for key, symbol in (("gamma16", "gamma16"), ("gamma8", "gamma8")):
        raw = bytes.fromhex(auxiliary[key]["bytes_hex"])
        assert len(raw) == auxiliary[key]["size"]
        out.append(f"static const unsigned char {symbol}[{len(raw)}] = {{")
        out.append("    " + ", ".join(f"0x{b:02x}" for b in raw))
        out += ["};"]
    out.append("")
    for key, symbol in (("_bitsPerPixelValues", "bitsPerPixelValues"), ("_colorConfigValues", "colorConfigValues")):
        entries = tables[key]["entries"]
        out.append(f"IONamedValue {symbol}[{len(entries)}] = {{")
        out.append("    " + ", ".join("{ " + str(e["value"]) + ", " + ("0" if e["name"] is None else json.dumps(e["name"])) + " }" for e in entries))
        out += ["};"]
    rate_names = {}
    for key in ("_Refresh_60_72_75", "_Refresh_60_70_75"):
        symbol = key[1:]
        rate_names[key] = symbol
        entries = tables[key]["entries"]
        raw = bytes.fromhex(tables[key]["bytes_hex"])
        assert list(struct.unpack("<" + "i" * (len(raw) // 4), raw)) == entries
        out.append(f"static int {symbol}[{len(entries)}] = {{ " + ", ".join(map(str, entries)) + " };")
    mapping = tables["_ATI_modeToRefreshRatesTable"]["entries"]
    out.append(f"ATI_ModeRefreshMap ATI_modeToRefreshRatesTable[{len(mapping)}] = {{")
    out.append("    " + ", ".join("{ " + str(e["mode"]) + ", " + ("0" if e["rates"] is None else rate_names[e["rates"]]) + " }" for e in mapping))
    out += ["};", "", "static ATI_CRTCRecord _AtiCRTCList[18] = {"]
    for rec in crtcs:
        b = bytes.fromhex(rec["bytes_hex"])
        assert len(b) == 30
        fields = [(0,1),(1,1),(2,1),(3,1),(4,2),(6,1),(7,1),(8,1),(9,1),
                  (10,2),(12,2),(14,2),(16,1),(17,1),(18,2),(20,2),
                  (22,1),(23,1),(24,1),(25,1),(26,1),(27,1),(28,2)]
        vals = [int.from_bytes(b[o:o+n], "little") for o,n in fields]
        out.append("    { " + ", ".join(f"0x{x:02x}" if n == 1 else f"0x{x:04x}" for (o,n),x in zip(fields,vals)) + " },")
    out += ["};", "", "IODisplayInfo AtiModeList[72] = {"]
    for rec in modes:
        b = bytes.fromhex(rec["bytes_hex"])
        assert len(b) == 136
        relocs = rec["relocations"]
        assert len(relocs) == 1 and relocs[0]["address"] == rec["address"] + 100
        addend = relocs[0]["addend"]
        assert addend >= 192 and (addend - 192) % 30 == 0
        crtci = (addend - 192) // 30
        assert crtci < 18
        enc = b[32:96].split(b"\0", 1)[0].decode("ascii")
        values = [s32(b, off) for off in [0,4,8,12,16]]
        bpp, colorspace = u32(b,24), u32(b,28)
        flags = u32(b,96)
        memory, scan = s32(b,104), s32(b,108)
        reserved1, clock = s32(b,112), s32(b,116)
        sw, sh, unavailable, reserved = (s32(b,x) for x in [120,124,128,132])
        out.append("    { " + ", ".join([
            *[str(v) for v in values], "0", str(bpp), str(colorspace), f'"{enc}"', str(flags),
            f"(void *)&_AtiCRTCList[{crtci}]", str(memory), str(scan), str(reserved1), str(clock),
            str(sw), str(sh), str(unavailable), "{ " + str(reserved) + " }"]) + " },")
    out += ["};", "", "static unsigned int AtiModeListCount = 72;", "#define ATI_MODE_COUNT 72", "", "#endif /* __ATIRAGE_MODES_H__ */", ""]
    generated = "\n".join(out)
    if check:
        if not OUTPUT.exists() or OUTPUT.read_text(encoding="ascii") != generated:
            raise SystemExit(f"generated display data differs from {OUTPUT}")
        print(f"display data matches contract: {len(crtcs)} CRTC records; {len(modes)} modes")
    else:
        OUTPUT.write_text(generated, encoding="ascii", newline="\n")
        print(f"wrote {OUTPUT}; {len(crtcs)} CRTC records and {len(modes)} modes")
    if resource_root is not None:
        failures = []
        for item in contract["resources"]:
            path = resource_root / item["path"]
            if not path.is_file():
                failures.append(f"missing: {item['path']}")
                continue
            data = path.read_bytes()
            if len(data) != item["size"] or hashlib.sha256(data).hexdigest().upper() != item["sha256"]:
                failures.append(f"hash/size mismatch: {item['path']}")
        if failures:
            raise SystemExit("resource manifest mismatch: " + "; ".join(failures))
        print(f"resource manifest matches: {len(contract['resources'])} files")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="compare generated header without writing")
    parser.add_argument("--resource-root", type=Path, help="also verify packaged resource files")
    args = parser.parse_args()
    emit(check=args.check, resource_root=args.resource_root)

