from pathlib import Path

from binrecon.source_map import build_source_map, defined_symbols, source_sites


def test_defined_symbols_groups_names_and_drops_undefined():
    document = {
        "symbols": [
            {"name": "_second", "address": 0x1000, "binding": "local", "section": "__text"},
            {"name": "_first", "address": 0x1000, "binding": "external", "section": "__text"},
            {"name": "_undefined", "address": 0x0, "binding": "external", "section": None},
            {"name": "_later", "address": 0x2000, "binding": "external", "section": "__text"},
        ]
    }

    assert defined_symbols(document) == {
        0x1000: ["_first", "_second"],
        0x2000: ["_later"],
    }


def test_source_sites_finds_objc_methods_and_c_functions(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Bus.m").write_text(
        "#import \"Bus.h\"\n"
        "\n"
        "@implementation PCIKernBus\n"
        "\n"
        "- (void)dealloc\n"
        "{\n"
        "}\n"
        "\n"
        "- initForResource:(id)resource item:(int)item shareable:(BOOL)flag\n"
        "{\n"
        "    return self;\n"
        "}\n"
        "\n"
        "+ (void)initialize\n"
        "{\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )
    (source_dir / "pci.c").write_text(
        "#include <stdio.h>\n"
        "\n"
        "static int helper(int value);\n"
        "\n"
        "int testSlotForID(unsigned slot)\n"
        "{\n"
        "    return slot;\n"
        "}\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[PCIKernBus dealloc]"] == [("src/driver/Bus.m", 5)]
    assert sites["-[PCIKernBus initForResource:item:shareable:]"] == [
        ("src/driver/Bus.m", 9)
    ]
    assert sites["+[PCIKernBus initialize]"] == [("src/driver/Bus.m", 14)]
    assert sites["_testSlotForID"] == [("src/driver/pci.c", 5)]
    assert "_helper" not in sites


def test_source_sites_keys_category_methods_separately_from_the_class(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "PCIKernBusPrivate.m").write_text(
        "@implementation PCIKernBus\n"
        "\n"
        "- (void)someMethod\n"
        "{\n"
        "}\n"
        "\n"
        "@end\n"
        "\n"
        "@implementation PCIKernBus (Private)\n"
        "\n"
        "- (void)someMethod\n"
        "{\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[PCIKernBus someMethod]"] == [
        ("src/driver/PCIKernBusPrivate.m", 3)
    ]
    assert sites["-[PCIKernBus(Private) someMethod]"] == [
        ("src/driver/PCIKernBusPrivate.m", 11)
    ]


def test_source_sites_joins_wrapped_multiline_selector(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "PCIKernBus.m").write_text(
        "@implementation PCIKernBus\n"
        "\n"
        "- (IOReturn)configAddress:(id)deviceDescription\n"
        "                   device:(unsigned char *)devNum\n"
        "                 function:(unsigned char *)funNum\n"
        "                      bus:(unsigned char *)busNum\n"
        "{\n"
        "    return kIOReturnSuccess;\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[PCIKernBus configAddress:device:function:bus:]"] == [
        ("src/driver/PCIKernBus.m", 3)
    ]


def test_source_sites_stops_lookahead_at_structural_boundary(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Boundary.m").write_text(
        "@implementation Foo\n"
        "- badMethodNoBody\n"
        "@end\n"
        "\n"
        "@implementation Bar\n"
        "- (void)bar\n"
        "{\n"
        "}\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[Bar bar]"] == [("src/driver/Boundary.m", 6)]
    assert "-[Foo badMethodNoBody]" not in sites
    assert not any(
        key.startswith("-[Foo") or key.startswith("+[Foo") for key in sites
    )


def test_source_sites_stops_lookahead_at_next_method_in_same_block(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Bad2.m").write_text(
        "@implementation Foo\n"
        "- badMethod1\n"
        "- (void)legitMethod\n"
        "{\n"
        "}\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[Foo legitMethod]"] == [("src/driver/Bad2.m", 3)]
    assert "-[Foo badMethod1]" not in sites


def test_source_sites_finds_no_space_method_declaration(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "VBoxVideo.m").write_text(
        "@implementation VBoxVideo\n"
        "\n"
        "-(unsigned long) getVideoRAMAddress\n"
        "{\n"
        "    return videoRAMAddress;\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[VBoxVideo getVideoRAMAddress]"] == [
        ("src/driver/VBoxVideo.m", 3)
    ]


def test_source_sites_joins_wrapped_no_space_selector(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "NE2K.m").write_text(
        "@implementation NE2K\n"
        "\n"
        "-(void) _NS8390TriggerSend:(unsigned int) len\n"
        "                    startPage:(int) start_page\n"
        "{\n"
        "    return;\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[NE2K _NS8390TriggerSend:startPage:]"] == [
        ("src/driver/NE2K.m", 3)
    ]


def test_source_sites_ignores_bare_arithmetic_inside_a_method_body(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Arith.m").write_text(
        "@implementation Foo\n"
        "\n"
        "-(void) compute\n"
        "{\n"
        "    int total = a\n"
        "        - b\n"
        "        + c;\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites == {"-[Foo compute]": [("src/driver/Arith.m", 3)]}


def _analysis(functions, sha256="A" * 64):
    return {"input": {"sha256": sha256}, "functions": functions}


def _function(address, size, names):
    return {
        "address": address,
        "size": size,
        "names": names,
        "blocks": [],
        "instructions": [],
        "calls": [],
        "confidence": 1.0,
    }


def test_build_source_map_buckets_every_function():
    analysis = _analysis(
        [
            _function(0x1000, 0x10, ["-[PCIKernBus init]"]),
            _function(0x1010, 0x10, ["_PCIBus_VERS_NUM"]),
            _function(0x1020, 0x10, ["_ambiguous"]),
            _function(0x1030, 0x10, ["_disputed"]),
        ]
    )
    macho = {"symbols": []}
    sites = {
        "-[PCIKernBus init]": [("src/driver/Bus.m", 12)],
        "_ambiguous": [("src/driver/a.c", 3), ("src/driver/b.c", 7)],
        "_disputed": [("src/driver/c.c", 5)],
    }

    document = build_source_map(analysis, macho, sites, disputed={0x1030})

    assert document["schema_version"] == "source-map-v1"
    assert document["reference_sha256"] == "A" * 64
    assert document["mapped"] == [
        {
            "address": 0x1000,
            "size": 0x10,
            "reference_names": ["-[PCIKernBus init]"],
            "source_path": "src/driver/Bus.m",
            "source_line": 12,
        }
    ]
    assert [entry["address"] for entry in document["unmapped"]] == [0x1010]
    assert [entry["address"] for entry in document["duplicate_candidates"]] == [0x1020]
    assert [entry["address"] for entry in document["boundary_disputed"]] == [0x1030]


def test_build_source_map_merges_symbol_table_names():
    analysis = _analysis([_function(0x2000, 0x10, [])])
    macho = {
        "symbols": [
            {"name": "_helper", "address": 0x2000, "binding": "local", "section": "__text"}
        ]
    }

    document = build_source_map(analysis, macho, {"_helper": [("src/driver/x.c", 4)]})

    assert document["mapped"][0]["reference_names"] == ["_helper"]
    assert document["mapped"][0]["source_line"] == 4
