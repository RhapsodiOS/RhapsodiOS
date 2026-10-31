import struct

import pytest

import check
import volume


class Patched(volume.Volume):
    """A volume whose reads see some bytes replaced."""
    patches = {}

    def read_at(self, off, n):
        b = bytearray(volume.Volume.read_at(self, off, n))
        for at, data in self.patches.items():
            for i, x in enumerate(data):
                if off <= at + i < off + n:
                    b[at + i - off] = x
        return bytes(b)


def test_the_apple_volume_is_consistent(toast):
    assert check.check(toast) == []


def _catalog_node_offset(v, node):
    return v.block_offset(v.vh.catalog_file.extents[0].start) + node * v.catalog.node_size


def _cases(v):
    vh = v.vol_base + 1024
    leaf = v.catalog.first_leaf
    node = v.catalog.node(leaf)
    at = _catalog_node_offset(v, leaf)
    bitmap = v.block_offset(v.vh.allocation_file.extents[0].start) + 20000 // 8
    return {
        "bitmap misses 1 owned blocks": {bitmap: bytes([v.read_at(bitmap, 1)[0] ^ 0x80])},
        "volume header counts 121 files": {vh + 32: struct.pack(">I", v.vh.file_count + 1)},
        "not cleanly unmounted": {vh + 4: struct.pack(">I", v.vh.attributes & ~0x100)},
        "keys out of order": {at + node.offsets[1] + 2: struct.pack(">I", 1)},
        "freeNodes 1007": {_catalog_node_offset(v, 0) + 14 + 26:
                           struct.pack(">I", v.catalog.free_nodes + 1)},
        "blink 77": {at + 4: struct.pack(">I", 77)},
    }


@pytest.mark.parametrize("expect", ["bitmap misses 1 owned blocks", "volume header counts 121 files",
                                    "not cleanly unmounted", "keys out of order",
                                    "freeNodes 1007", "blink 77"])
def test_each_kind_of_damage_is_reported(toast, toast_location, expect):
    Patched.patches = _cases(toast)[expect]
    damaged = Patched(*toast_location)
    try:
        problems = check.check(damaged)
    finally:
        damaged.close()
    assert any(expect in p for p in problems), problems
