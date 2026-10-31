import hfsfmt


def test_relstring_folds_case_but_not_length():
    assert hfsfmt.relstring_compare(b"abc", b"ABC") == 0
    assert hfsfmt.relstring_compare(b"abc", b"ABD") == -1
    assert hfsfmt.relstring_compare(b"ab", b"abc") == -1
    assert hfsfmt.relstring_compare(b"b", b"A") == 1


def test_unicode_compare_folds_case_and_skips_ignorables():
    assert hfsfmt.unicode_compare([0x41], [0x61]) == 0
    assert hfsfmt.unicode_compare([0x200C, 0x61], [0x61]) == 0     # ZWNJ is ignorable
    assert hfsfmt.unicode_compare([0x0000], [0x7A]) == 1            # NUL folds to 0xFFFF
    assert hfsfmt.unicode_compare([0x61], [0x62]) == -1
    assert hfsfmt.unicode_compare([0x61, 0x62], [0x61]) == 1


def test_the_apple_volume_reads(toast):
    assert toast.plus and toast.wrapper is not None
    assert toast.wrapper.al_blk_siz == 73728
    assert (toast.block_size, toast.total_blocks, toast.free_blocks) == (4096, 165402, 82748)
    assert (toast.vh.file_count, toast.vh.folder_count) == (120, 51)
    assert (toast.catalog.node_size, toast.catalog.tree_depth, toast.catalog.leaf_records) == (4096, 2, 344)
    walk = toast.walk()
    assert len(walk) == 171
    assert sum(1 for p, e in walk if not e.is_dir) == 120


def test_the_apple_volume_file_contents(toast):
    files = dict((p, e) for p, e in toast.walk() if not e.is_dir)
    pdf = toast.read_file(files["/About AppleScript Studio.pdf"])
    assert len(pdf) == 52179
    assert pdf.startswith(b"%PDF")
