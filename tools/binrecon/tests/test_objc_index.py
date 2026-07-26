import struct

from binrecon.macho import objc_methods_from_sections

BASE = 0x1000


def _build():
    """One class with an instance and a class method, plus one category."""
    blob = bytearray(0x200)

    def put(offset, *values):
        struct.pack_into(f"<{len(values)}I", blob, offset, *values)

    def put_str(offset, text):
        raw = text.encode("ascii") + b"\0"
        blob[offset:offset + len(raw)] = raw

    # objc_module: version, size, name, symtab
    put(0x00, 0, 16, BASE + 0x100, BASE + 0x20)
    # objc_symtab: sel_ref_cnt, refs, then cls_def_cnt/cat_def_cnt as u16 pair
    put(0x20, 0, 0)
    struct.pack_into("<HH", blob, 0x28, 1, 1)
    put(0x2C, BASE + 0x40, BASE + 0x80)
    # objc_class: isa, super, name, version, info, instance_size, ivars, methodList
    put(0x40, BASE + 0x60, 0, BASE + 0x110, 0, 0, 0, 0, BASE + 0xA0)
    # metaclass: only isa/name/methodList matter
    put(0x60, 0, 0, BASE + 0x110, 0, 0, 0, 0, BASE + 0xC0)
    # objc_category: category_name, class_name, instance_methods, class_methods
    put(0x80, BASE + 0x120, BASE + 0x110, BASE + 0xE0, BASE + 0x170)
    # method lists: obsolete, count, then (sel, types, imp)
    put(0xA0, 0, 1, BASE + 0x130, BASE + 0x140, 0x2000)
    put(0xC0, 0, 1, BASE + 0x150, BASE + 0x140, 0x2100)
    put(0xE0, 0, 1, BASE + 0x160, BASE + 0x140, 0x2200)
    put(0x170, 0, 1, BASE + 0x190, BASE + 0x140, 0x2300)

    put_str(0x100, "Test.m")
    put_str(0x110, "Thing")
    put_str(0x120, "Extra")
    put_str(0x130, "doThing")
    put_str(0x140, "v8@8:12")
    put_str(0x150, "makeThing:")
    put_str(0x160, "extraThing")
    put_str(0x190, "makeExtra")
    return bytes(blob)


SECTIONS = [
    {"name": "__OBJC,__module_info", "address": BASE, "size": 16, "offset": 0},
    {"name": "__OBJC,__blob", "address": BASE, "size": 0x200, "offset": 0},
]


def test_recovers_instance_class_and_category_methods():
    index = objc_methods_from_sections(_build(), SECTIONS)

    assert index == {
        0x2000: ["-[Thing doThing]"],
        0x2100: ["+[Thing makeThing:]"],
        0x2200: ["-[Thing(Extra) extraThing]"],
        0x2300: ["+[Thing(Extra) makeExtra]"],
    }


def test_returns_empty_when_there_is_no_module_info():
    sections = [{"name": "__TEXT,__text", "address": BASE, "size": 4, "offset": 0}]

    assert objc_methods_from_sections(b"\0" * 16, sections) == {}


def test_truncated_symtab_does_not_raise():
    """A module whose symtab pointer is valid but the buffer is cut off
    part-way through the symtab must be skipped, not raise."""
    blob = bytearray(0x24)

    def put(offset, *values):
        struct.pack_into(f"<{len(values)}I", blob, offset, *values)

    # objc_module: version, size, name, symtab
    put(0x00, 0, 16, BASE, BASE + 0x20)
    payload = bytes(blob)

    sections = [
        {"name": "__OBJC,__module_info", "address": BASE, "size": 16, "offset": 0},
        {"name": "__OBJC,__blob", "address": BASE, "size": 0x200, "offset": 0},
    ]

    result = objc_methods_from_sections(payload, sections)
    assert result == {}
