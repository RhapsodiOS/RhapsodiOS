#!/usr/bin/env python3
"""Check the rebuilt i386 class layout, method inventory and imports.

This is an ABI/inventory check, not machine-code equivalence.
"""
from pathlib import Path
import argparse
import struct

from binrecon.macho import read_macho

def abi(path):
    document = read_macho(path)
    payload = path.read_bytes()

    def offset(address):
        for section in document["sections"]:
            if section["address"] <= address < section["address"] + section["size"]:
                return section["offset"] + address - section["address"]
        raise ValueError(f"unmapped Objective-C metadata address {address:#x}")

    def word(address):
        return struct.unpack_from("<I", payload, offset(address))[0]

    def text(address):
        start = offset(address)
        return payload[start:payload.index(b"\0", start)].decode("latin1")

    classes = {}
    section = next(s for s in document["sections"] if s["name"] == "__OBJC,__class")
    for address in range(section["address"], section["address"] + section["size"], 40):
        # Objective-C 1.0: instance_size at +20, ivar-list pointer at +24.
        size = word(address + 20)
        variables = word(address + 24)
        ivars = []
        if variables:
            for index in range(word(variables)):
                entry = variables + 4 + index * 12
                ivars.append([text(word(entry)), text(word(entry + 4)), word(entry + 8)])
        classes[text(word(address + 8))] = {
            "super": text(word(address + 4)), "size": size, "ivars": ivars,
        }
    return classes


def verify(reference, rebuilt):
    ref, new = read_macho(reference), read_macho(rebuilt)
    if new["input"]["architecture"] != "i386":
        raise ValueError("rebuilt driver is not i386")
    def methods(document):
        return {s["name"] for s in document["symbols"]
                if s["section"] == "__TEXT,__text" and s["name"].startswith(("-[", "+["))}
    if len(methods(ref)) != 59 or methods(ref) != methods(new):
        raise ValueError("59-method inventory differs (including address zero)")
    def imports(document):
        return {s["name"] for s in document["symbols"] if s["section"] is None}
    # The reconstructed multicast copy uses the kernel's bcopy instead of
    # the original inline six-byte copy. No other import difference is allowed.
    if imports(ref) - imports(new) or imports(new) - imports(ref) != {"_bcopy"}:
        raise ValueError("external symbol inventory differs")
    reference_classes, rebuilt_classes = abi(reference), abi(rebuilt)
    # The original opaque EEPROM union and the recovered 128-byte buffer have
    # identical offsets and total instance size; their type encodings differ.
    for classes in (reference_classes, rebuilt_classes):
        for ivar in classes["i82595eeprom"]["ivars"]:
            if ivar[0] == "contents":
                if ivar[1] not in ("(?)", "[128C]"):
                    raise ValueError("unexpected EEPROM contents representation")
                ivar[1] = "128-byte EEPROM storage"
    if len(reference_classes) != 9 or reference_classes != rebuilt_classes:
        raise ValueError("class hierarchy, size or ivar layout differs")
    return "PASS: i386, 59 methods, 9 class layouts; only added import is documented _bcopy"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("rebuilt", type=Path)
    args = parser.parse_args()
    print(verify(args.reference, args.rebuilt))
