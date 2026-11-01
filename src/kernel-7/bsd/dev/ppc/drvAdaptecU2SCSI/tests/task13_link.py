"""Private PPC arenas: compiled transport/API and accepted native dependencies.

This is a supplementary mixed closure, not a rebuilt kernel. Only relocations
from the actual Mach-O objects are applied. Reference instructions stay exact.
"""

import hashlib
import struct
from binrecon.macho import load_image


def pack(*values):
    return struct.pack(">" + "I" * len(values), *values)


def label(value):
    raw = value.encode()
    if len(raw) > 16:
        raise ValueError("arena Mach-O name exceeds field")
    return raw.ljust(16, b"\0")


def link(reference, objects, destination):
    original, image = load_image(reference)
    if image["input"]["sha256"] != "D01D748C10117FBFCEB25F99D88A63895C3BAC6C09A5110AD358E583316494BD":
        raise ValueError("HIM arena reference identity differs")
    segments, symbols, definitions, owners = [], [], {}, {}
    for segment in image["extensions"]["macho"]["segments"]:
        if not segment["size"]:
            continue
        segments.append({**segment, "data": bytearray(original[segment["offset"]:segment["offset"]+segment["file_size"]]),
                         "sections": [dict(s) for s in image["sections"] if s["name"].split(",")[0] == segment["name"]]})
    for symbol in image["symbols"]:
        if symbol["section"]:
            symbols.append(dict(symbol))
            definitions[symbol["name"]] = symbol["address"]
    native = []
    for index, path in enumerate(objects):
        raw, obj = load_image(path)
        if (obj["input"]["architecture"], obj["input"]["endianness"],
                obj["extensions"]["macho"]["header"]["file_type"]) != ("ppc", "big", 1):
            raise ValueError("HIM arena requires actual PPC objects")
        base, name = 0x1000000 + index * 0x100000, "__AU2" + str(index)
        size = max(s["address"] + s["size"] for s in obj["sections"])
        data = bytearray(size)
        sections = []
        for section in obj["sections"]:
            if section["offset"]:
                data[section["address"]:section["address"]+section["size"]] = raw[section["offset"]:section["offset"]+section["size"]]
            sections.append({**section, "name": name+","+section["name"].split(",")[1],
                             "address": base+section["address"], "arena_offset": section["address"]})
        for symbol in obj["symbols"]:
            if symbol["section"] and symbol["binding"] == "external":
                if symbol["name"] in owners:
                    raise ValueError("duplicate native HIM arena definition")
                section = next(s for s in obj["sections"] if s["name"] == symbol["section"])
                following = [s["address"] for s in obj["symbols"] if s["section"] == symbol["section"] and
                             s["binding"] == "external" and s["address"] > symbol["address"]]
                end = min(following, default=section["address"]+section["size"])
                owners[symbol["name"]] = {"object": str(path), "source_address": symbol["address"],
                                          "arena_address": base+symbol["address"], "size": end-symbol["address"],
                                          "body_sha256": hashlib.sha256(data[symbol["address"]:end]).hexdigest().upper()}
                definitions[symbol["name"]] = base+symbol["address"]
        item = {"name": name, "address": base, "size": (size+4095)&~4095,
                "file_size": size, "permissions": "rwx", "data": data, "sections": sections}
        native.append((obj, item))
        segments.append(item)
    for symbol in symbols:
        if symbol["name"] in owners:
            symbol["name"] = "_au2_reference_" + symbol["name"].removeprefix("_")
    relocations = []
    for obj, segment in native:
        base, data = segment["address"], segment["data"]
        for symbol in obj["symbols"]:
            if symbol["section"] and symbol["binding"] == "external":
                symbols.append({**symbol, "address": base+symbol["address"],
                                "section": segment["name"]+","+symbol["section"].split(",")[1]})
        for relocation in obj["extensions"]["macho"]["relocations"]:
            if relocation["kind"] == "ppc-pair-16-absolute":
                continue
            offset = relocation["address"]
            if not 0 <= offset <= len(data)-4:
                raise ValueError("HIM arena relocation exceeds object")
            if relocation["external"]:
                if relocation["target"] not in definitions:
                    raise ValueError("unresolved HIM arena import: " + relocation["target"])
                target = definitions[relocation["target"]] + relocation["addend"]
            else:
                section = next((s for s in obj["sections"] if s["name"] == relocation["target"]), None)
                if section is None:
                    raise ValueError("unresolved HIM arena local relocation")
                target = base + section["address"] + relocation["addend"]
            word = int.from_bytes(data[offset:offset+4], "big")
            kind = relocation["kind"]
            if kind == "ppc-br24-24-pc-relative":
                displacement = target-(base+offset)
                if displacement % 4 or not -0x2000000 <= displacement < 0x2000000:
                    raise ValueError("HIM arena branch exceeds actual PPC range")
                word = (word & 0xfc000003) | (displacement & 0x3fffffc)
            elif kind == "ppc-ha16-32-absolute":
                word = (word & 0xffff0000) | (((target+0x8000) >> 16) & 0xffff)
            elif kind == "ppc-lo16-32-absolute":
                word = (word & 0xffff0000) | (target & 0xffff)
            elif kind == "vanilla-32-absolute":
                word = target
            elif (kind == "ppc-vanilla-32-absolute" and
                  obj["input"]["sha256"] == "67AA7E935CBBC44826838BF5D8D6943497E706722FAE93EEBB1716231F0FC062" and
                  not relocation["scattered"] and
                  relocation["width"] == 4 and not relocation["pc_relative"] and
                  relocation["section"] == "__DATA,__data" and offset % 4 == 0 and
                  ((relocation["external"] and word == 0 and relocation["addend"] == 0) or
                   (not relocation["external"] and relocation["target"] == "__DATA,__data" and
                    word == relocation["addend"] and (offset, word) in
                    ((240, 0), (244, 120), (1436, 252), (1448, 548), (1452, 844), (1456, 1140))))):
                word = target
            elif (kind == "ppc-sectdiff-32-absolute" and relocation["scattered"] and
                  relocation["section"] == "__TEXT,__const" and relocation["target"] == "__TEXT,__text"):
                # Both endpoints translate by this object's one arena base.
                # The authenticated compiler's relative switch delta stays exact.
                if data[offset:offset+4].hex().upper() != relocation["original_bytes"]:
                    raise ValueError("HIM arena switch delta changed")
            else:
                raise ValueError("unsupported HIM arena relocation: " + kind)
            data[offset:offset+4] = pack(word & 0xffffffff)
            relocations.append({**relocation, "arena_address": base+offset, "resolved_target": target})
    command_size = sum(56+68*len(s["sections"]) for s in segments)+24
    cursor = (28+command_size+4095)&~4095
    commands, chunks, indices = [], [], {}
    for segment in segments:
        start = cursor
        chunks.append((start, bytes(segment["data"])))
        permissions = sum(bit for char, bit in (("r", 1), ("w", 2), ("x", 4)) if char in segment["permissions"])
        command = pack(1, 56+68*len(segment["sections"]))+label(segment["name"])+pack(
            segment["address"], segment["size"], start, len(segment["data"]), 7, permissions, len(segment["sections"]), 0)
        for section in segment["sections"]:
            indices[section["name"]] = len(indices)+1
            address = section["address"]
            zero_fill = not section["offset"]
            command += label(section["name"].split(",")[1])+label(segment["name"])+pack(
                address, section["size"], 0 if zero_fill else start+address-segment["address"],
                2, 0, 0, 1 if zero_fill else 0, 0, 0)
        commands.append(command)
        cursor = (start+len(segment["data"])+4095)&~4095
    strings, records = bytearray(b"\0"), bytearray()
    for symbol in symbols:
        offset = len(strings)
        strings += symbol["name"].encode()+b"\0"
        records += struct.pack(">IBBHI", offset, 0xf if symbol["binding"] == "external" else 0xe,
                               indices[symbol["section"]], 0, symbol["address"])
    commands.append(pack(2, 24, cursor, len(symbols), cursor+len(records), len(strings)))
    result = bytearray(cursor+len(records)+len(strings))
    result[:28] = pack(0xfeedface, 18, 0, 2, len(commands), command_size, 0)
    result[28:28+command_size] = b"".join(commands)
    for offset, raw in chunks:
        result[offset:offset+len(raw)] = raw
    result[cursor:] = records+strings
    destination.write_bytes(result)
    _, check = load_image(destination)
    if len(check["symbols"]) != len(symbols):
        raise ValueError("HIM arena emitted symbol table differs")
    return {"sha256": hashlib.sha256(result).hexdigest().upper(), "definitions": owners,
            "relocations": relocations, "reference_sha256": image["input"]["sha256"],
            "objects": {str(path): hashlib.sha256(path.read_bytes()).hexdigest().upper() for path in objects}}
