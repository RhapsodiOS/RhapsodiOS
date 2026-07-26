import struct

import pytest

from binrecon.objc_abi import ObjcReader, read_classes

BASE = 0x1000


def build_blob(prefix="<"):
    """One class with a superclass, two ivars, one instance and one class method."""
    blob = bytearray(0x300)

    def put(offset, *values):
        struct.pack_into(f"{prefix}{len(values)}I", blob, offset, *values)

    def put_str(offset, text):
        raw = text.encode("ascii") + b"\0"
        blob[offset:offset + len(raw)] = raw

    # objc_symtab: sel_ref_cnt, refs, then cls_def_cnt/cat_def_cnt as u16 pair
    put(0x20, 0, 0)
    struct.pack_into(f"{prefix}HH", blob, 0x28, 1, 0)
    put(0x2C, BASE + 0x40)
    # objc_class: isa, super, name, version, info, instance_size, ivars, methodList
    put(0x40, BASE + 0x60, BASE + 0x1C0, BASE + 0x110, 0, 1, 12, BASE + 0x200, BASE + 0xA0)
    # metaclass: isa, super, name, version, info, instance_size, ivars, methodList
    put(0x60, 0, 0, BASE + 0x110, 0, 2, 0, 0, BASE + 0xC0)
    # method lists: obsolete, count, then (sel, types, imp)
    put(0xA0, 0, 1, BASE + 0x130, BASE + 0x140, 0x2000)
    put(0xC0, 0, 1, BASE + 0x150, BASE + 0x140, 0x2100)
    # objc_ivar_list: count, then (name, type, offset)
    put(0x200, 2)
    put(0x204, BASE + 0x170, BASE + 0x180, 4)
    put(0x210, BASE + 0x190, BASE + 0x1A0, 8)

    put_str(0x110, "Thing")
    put_str(0x130, "doThing")
    put_str(0x140, "v8@8:12")
    put_str(0x150, "makeThing:")
    put_str(0x170, "_count")
    put_str(0x180, "I")
    put_str(0x190, "_name")
    put_str(0x1A0, "@")
    put_str(0x1C0, "NSObject")
    return bytes(blob)


SECTIONS = [{"name": "__OBJC,__blob", "address": BASE, "size": 0x300, "offset": 0}]


def test_reads_class_layout_and_ivars():
    reader = ObjcReader(build_blob(), SECTIONS, "little")

    assert read_classes(reader, BASE + 0x20) == [{
        "name": "Thing",
        "superclass": "NSObject",
        "instance_size": 12,
        "info": 1,
        "ivars": [
            {"name": "_count", "type": "I", "offset": 4},
            {"name": "_name", "type": "@", "offset": 8},
        ],
        "instance_methods": [{"selector": "doThing", "types": "v8@8:12"}],
        "class_methods": [{"selector": "makeThing:", "types": "v8@8:12"}],
    }]


def test_reads_big_endian_the_same_way():
    reader = ObjcReader(build_blob(">"), SECTIONS, "big")
    assert read_classes(reader, BASE + 0x20)[0]["name"] == "Thing"


def test_recovers_a_prebound_selector_from_the_symbol_table():
    """A selector pointer outside the image is resolved via the symbol table."""
    blob = bytearray(build_blob())
    # Point the instance method's selector at an address no section backs.
    struct.pack_into("<I", blob, 0xA8, 0x41406990)

    reader = ObjcReader(bytes(blob), SECTIONS, "little",
                        method_names={0x2000: "-[Thing doThing]"})

    assert read_classes(reader, BASE + 0x20)[0]["instance_methods"] == [
        {"selector": "doThing", "types": "v8@8:12"}
    ]


def test_an_unresolvable_prebound_selector_is_an_error():
    from binrecon.objc_abi import ObjcAbiError

    blob = bytearray(build_blob())
    struct.pack_into("<I", blob, 0xA8, 0x41406990)
    reader = ObjcReader(bytes(blob), SECTIONS, "little")

    with pytest.raises(ObjcAbiError, match="outside the image"):
        read_classes(reader, BASE + 0x20)


def test_method_symbol_index_keys_on_implementation_address():
    from binrecon.objc_abi import method_symbol_index

    document = {"symbols": [
        {"name": "-[Thing doThing]", "address": 0x2000, "section": "__TEXT,__text"},
        {"name": "+[Thing(Extra) make]", "address": 0x2100, "section": "__TEXT,__text"},
        {"name": "_NotAMethod", "address": 0x2200, "section": "__TEXT,__text"},
        {"name": "-[Thing imported]", "address": 0, "section": None},
    ]}

    assert method_symbol_index(document) == {
        0x2000: "-[Thing doThing]",
        0x2100: "+[Thing(Extra) make]",
    }


def build_module_blob(prefix="<"):
    """A module defining no classes and one category on NSCoder."""
    blob = bytearray(0x300)

    def put(offset, *values):
        struct.pack_into(f"{prefix}{len(values)}I", blob, offset, *values)

    def put_str(offset, text):
        raw = text.encode("ascii") + b"\0"
        blob[offset:offset + len(raw)] = raw

    # objc_module: version, size, name, symtab
    put(0x00, 7, 16, BASE + 0x100, BASE + 0x20)
    put(0x20, 0, 0)
    struct.pack_into(f"{prefix}HH", blob, 0x28, 0, 1)
    put(0x2C, BASE + 0x80)
    # objc_category: category_name, class_name, instance_methods, class_methods
    put(0x80, BASE + 0x120, BASE + 0x110, BASE + 0xE0, 0)
    put(0xE0, 0, 1, BASE + 0x160, BASE + 0x140, 0x2200)

    put_str(0x100, "NSGeometry.m")
    put_str(0x110, "NSCoder")
    put_str(0x120, "NSGeometryCoding")
    put_str(0x140, "{?=ff}8@8:12")
    put_str(0x160, "decodePoint")
    return bytes(blob)


MODULE_SECTIONS = [
    {"name": "__OBJC,__module_info", "address": BASE, "size": 16, "offset": 0},
    {"name": "__OBJC,__blob", "address": BASE, "size": 0x300, "offset": 0},
]


def test_reads_a_module_with_a_category():
    from binrecon.objc_abi import read_modules_from_sections

    modules = read_modules_from_sections(build_module_blob(), MODULE_SECTIONS, "little")

    assert modules == {"NSGeometry.m": {
        "schema_version": "abi-v1",
        "module": "NSGeometry.m",
        "classes": [],
        "categories": [{
            "name": "NSGeometryCoding",
            "class": "NSCoder",
            "instance_methods": [
                {"selector": "decodePoint", "types": "{?=ff}8@8:12"}
            ],
            "class_methods": [],
        }],
        "text_symbols": [],
        "data_symbols": [],
    }}
