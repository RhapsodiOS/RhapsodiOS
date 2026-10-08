import unicodedata

import pytest

import builder
import check
import content
import scenario
import volume

SIZE = 40 * 1024 * 1024


def nfc(s):
    return unicodedata.normalize("NFC", s)


@pytest.fixture(params=["hfsplus", "hfs", "wrapped", "hfsplus8k"])
def built(request, tmp_path):
    path = tmp_path / ("%s.img" % request.param)
    path.write_bytes(builder.BUILDERS[request.param](scenario.base_manifest(), SIZE))
    v = volume.Volume(str(path))
    yield request.param, v
    v.close()


def test_built_volume_is_consistent(built):
    assert check.check(built[1]) == []


def test_built_volume_holds_the_manifest(built):
    flavour, v = built
    walk = v.walk()
    got = dict((nfc(p[1:]), None if e.is_dir else e.data.logical_size) for p, e in walk)
    assert got == scenario.tree(scenario.base_manifest())
    for p, e in walk:
        if not e.is_dir:
            assert v.read_file(e) == content.data(nfc(p[1:]), e.data.logical_size), p


def test_built_volume_exercises_the_interesting_paths(built):
    flavour, v = built
    assert v.catalog.tree_depth >= 2
    assert v.extents.leaf_records >= 1          # frag.bin overflows its record
    assert v.total_blocks > 4096                # more than one bitmap I/O block
    assert (v.wrapper is not None) == (flavour == "wrapped")
    assert v.plus == (flavour != "hfs")


def test_hfsplus8k_uses_8k_allocation_blocks(tmp_path):
    # i386 maps 8K-block volumes through BestBlockSizeFit, not the extent table
    path = tmp_path / "hfsplus8k.img"
    path.write_bytes(builder.BUILDERS["hfsplus8k"](scenario.base_manifest(), SIZE))
    with volume.Volume(str(path)) as v:
        assert v.block_size == 8192 and v.extents.leaf_records >= 1


def test_hfs_plus_names_are_stored_decomposed(tmp_path):
    path = tmp_path / "p.img"
    path.write_bytes(builder.build_plus(scenario.base_manifest(), SIZE))
    with volume.Volume(str(path)) as v:
        names = [e.name for e in v.entries().values()]
    assert (0x0065, 0x0301) in [n[3:5] for n in names if len(n) > 4]


def test_cksum_matches_posix():
    assert content.cksum(b"") == 4294967295
    assert content.cksum(b"hello\n") == 3015617425
    assert content.cksum(b"a") == 1220704766


def test_content_is_the_name_repeated():
    assert content.data("ab", 7) == b"ab\nab\na"
    assert content.data("x", 0) == b""
