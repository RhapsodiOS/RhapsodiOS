#!/usr/bin/env python3
"""Check i386 architecture, Objective-C method inventory, and class ABI."""

import argparse
from pathlib import Path
import struct

from binrecon.macho import read_macho


REFERENCE_SHA256 = "2BF1F8563BABD7CDC4C7BA625E9963033A6B56BFE237A43308707944228AACE8"


def abi(path: Path, document: dict) -> dict:
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


def methods(document):
    return {
        symbol["name"] for symbol in document["symbols"]
        if symbol["section"] == "__TEXT,__text"
        and symbol["name"].startswith(("-[", "+["))
    }


def verify(reference: Path, rebuilt: Path) -> str:
    original = read_macho(reference)
    candidate = read_macho(rebuilt)
    if original["input"]["sha256"].upper() != REFERENCE_SHA256:
        raise ValueError("reference binary SHA-256 mismatch")
    if candidate["input"]["architecture"] != "i386":
        raise ValueError("rebuilt driver is not i386")
    ref_methods, new_methods = methods(original), methods(candidate)
    if len(ref_methods) != 39 or ref_methods != new_methods:
        raise ValueError("Objective-C method inventory differs from the reference")
    ref_classes = abi(reference, original)
    new_classes = abi(rebuilt, candidate)
    if len(ref_classes) != 3 or ref_classes != new_classes:
        raise ValueError("Objective-C class hierarchy, sizes, or ivars differ")
    if ref_classes["EtherExpress16"]["size"] != 492:
        raise ValueError("unexpected reference EtherExpress16 instance size")
    return "PASS: i386, 39 Objective-C methods, and 3 exact class layouts"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reference", type=Path)
    parser.add_argument("rebuilt", type=Path)
    arguments = parser.parse_args()
    print(verify(arguments.reference, arguments.rebuilt))
