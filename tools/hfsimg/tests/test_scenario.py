import content
import scenario


def test_write_model():
    t = scenario.expected_after_write(scenario.base_manifest())
    assert "frag.bin" not in t and "w/d19" not in t and "w/f025" not in t
    assert t["w/r010"] == scenario.new_file_size(10)
    assert t["w/d00/f011"] == scenario.new_file_size(11)
    assert t["w/big"] == scenario.BIG_SIZE and t["top.txt"] == 5000
    assert t["w/d05/x"] == 100 and t["w/d05"] is None
    assert scenario.content_name("w/r010") == "w/f010"
    assert scenario.content_name("top.txt") == "top.txt"
    # two files grown in turn, so the kernel inserts extents-overflow records
    size = scenario.APPEND_ROUNDS * scenario.APPEND_CHUNK
    assert t["w/ga"] == size and t["w/gb"] == size


def test_appends_keep_generated_contents():
    for name in ("w/ga", "w/gb"):
        unit = len(name) + 1                    # content.data repeats name + "\n"
        chunk = content.data(name, scenario.APPEND_CHUNK)
        assert chunk * 3 == content.data(name, 3 * scenario.APPEND_CHUNK)
        assert scenario.APPEND_CHUNK % unit == 0


def test_write_script_mirrors_the_model():
    s = scenario.write_script("/dev/hd1a")
    assert "/mnt/mount_hfs /dev/hd1a /mnt/h" in s
    assert "expr $i \\* 1499 % 30000" in s
    assert "mv w/f010 w/r010" in s and "rm frag.bin" in s
    assert "P w/big %d" % scenario.BIG_SIZE in s
    assert "A w/ga %d; A w/gb %d" % (scenario.APPEND_CHUNK, scenario.APPEND_CHUNK) in s
    assert s.rstrip().endswith("sync")


def test_read_script_options():
    assert "/mnt/mount_hfs -o ro /dev/hd1a" in scenario.read_script("/dev/hd1a", read_only=True)
    s = scenario.read_script("/dev/hd1a", sample=["a b", "c"])
    assert "cksum './a b'; cksum './c'" in s
    # the Apple volume has "What's New.pdf"
    assert "cksum './What'\\''s New.pdf'" in scenario.read_script("/dev/hd1a", sample=["What's New.pdf"])


def test_parsers():
    assert scenario.parse_list(".\n./a\n./a/b c\n") == {"a", "a/b c"}
    assert scenario.parse_sums("1 2 ./a b\n3 4 ./c\n") == {"a b": (1, 2), "c": (3, 4)}
