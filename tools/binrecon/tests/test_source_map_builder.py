from pathlib import Path

from binrecon.source_map import defined_symbols, source_sites


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
