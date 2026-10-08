import importlib.util
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "export_rebuilt_ida", ROOT / "export_rebuilt_ida.py"
)
EXPORTER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EXPORTER)


def test_rebuilt_class_alias_follows_name_relocations_after_section_shift():
    image = bytearray(0x200)
    image[0x180:0x180 + len(b"Object\0ATI_BIOS\0")] = b"Object\0ATI_BIOS\0"
    macho = {
        "sections": [{"name": "__OBJC,__class", "address": 0x512C, "size": 0x40},
                     {
            "name": "__OBJC,__class_names",
            "offset": 0x180,
            "size": 0x20,
        }],
        "relocations": [
            {"address": 0x5128, "target": "__OBJC,__class_names", "addend": 0},
            {"address": 0x5130, "target": "__OBJC,__class_names", "addend": 0},
            {"address": 0x5134, "target": "__OBJC,__class_names", "addend": 7},
        ],
    }

    aliases = EXPORTER._rebuilt_data_aliases(macho, image)

    assert aliases == {0x5130: "ATI_BIOS_class_ext"}


def test_rebuilt_class_alias_rejects_missing_name_relocation_pair():
    image = bytearray(0x200)
    image[0x180:0x180 + len(b"Object\0ATI_BIOS\0")] = b"Object\0ATI_BIOS\0"
    macho = {
        "sections": [{"name": "__OBJC,__class", "address": 0x512C, "size": 0x40}, {
            "name": "__OBJC,__class_names",
            "offset": 0x180,
            "size": 0x20,
        }],
        "relocations": [
            {"address": 0x5130, "target": "__OBJC,__class_names", "addend": 0},
            {"address": 0x5134, "target": "__OBJC,__class_names", "addend": 8},
        ],
    }

    with pytest.raises(ValueError, match="unique Object/ATI_BIOS relocation pair"):
        EXPORTER._rebuilt_data_aliases(macho, image)
