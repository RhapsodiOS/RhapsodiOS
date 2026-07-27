import json
from pathlib import Path

import pytest

import binrecon.schema as schema
from binrecon.source_map import (
    build_source_map,
    defined_symbols,
    scope_analysis,
    source_sites,
)


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


def test_source_sites_joins_wrapped_selector_across_inline_comments(tmp_path):
    """A comment inside a wrapped signature must not become a keyword.

    Selector keywords are read as the word following each argument name, so
    a comment between them -- drvSCSITape's SCSITape.m annotates both the
    first line of initSCSITape: and a continuation line of executeRequest:
    this way -- otherwise yields "initSCSITape:/*:lun:...".
    """
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "SCSITape.m").write_text(
        "@implementation SCSITape\n"
        "\n"
        "- (stInitReturn_t) initSCSITape:(int)iunit \t/* IODevice unit # */\n"
        "    target:\t\t(u_char) stTarget\n"
        "    lun:\t\t(u_char) stLun\n"
        "{\n"
        "    return ST_INIT_SUCCESS;\n"
        "}\n"
        "\n"
        "- (sc_status_t) executeRequest: (IOSCSIRequest *)scsiReq\n"
        "    buffer:(void *) buffer /* data destination */\n"
        "    client:(vm_task_t) client\n"
        "{\n"
        "    return SR_IOST_GOOD;\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[SCSITape initSCSITape:target:lun:]"] == [
        ("src/driver/SCSITape.m", 3)
    ]
    assert sites["-[SCSITape executeRequest:buffer:client:]"] == [
        ("src/driver/SCSITape.m", 10)
    ]


def test_source_sites_reads_a_selector_whose_argument_type_nests_parentheses(tmp_path):
    """A function-pointer argument nests parentheses inside its type.

    Stripping only innermost pairs leaves the outer type's closing paren
    behind, and the segment walk then reads it as the keyword, yielding
    "sortUsingFunction:)context:". Kits/Foundation/NSArray.m declares three
    such methods.
    """
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "NSArray.m").write_text(
        "@implementation NSArray\n"
        "\n"
        "- (void)sortUsingFunction:(int (*)(id, id, void *))compare\n"
        "    context:(void *)context\n"
        "{\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[NSArray sortUsingFunction:context:]"] == [
        ("src/driver/NSArray.m", 3)
    ]


def test_source_sites_still_finds_single_line_selector_with_trailing_comment(tmp_path):
    """A comment after a one-line signature already worked; keep it working.

    Both shapes occur: an accessor with no keyword at all, and one whose
    single keyword is followed by the comment.
    """
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "SCSITape.m").write_text(
        "@implementation SCSITape\n"
        "\n"
        "- (int) target\t\t\t/* Set only during initialization */\n"
        "{\n"
        "    return (int) _target;\n"
        "}\n"
        "\n"
        "- (void) setTarget:(int)target\t/* Initialization only */\n"
        "{\n"
        "    _target = target;\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[SCSITape target]"] == [("src/driver/SCSITape.m", 3)]
    assert sites["-[SCSITape setTarget:]"] == [("src/driver/SCSITape.m", 8)]


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


def test_source_sites_skips_multiline_c_prototype_and_finds_multiline_definition(
    tmp_path,
):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "PCIResourceDriver.c").write_text(
        "#include <stdio.h>\n"
        "\n"
        "static int Get_Maximums(int x);\n"
        "\n"
        "static int Get_ConfigSpace(unsigned int *count, char *values,\n"
        "                           unsigned int dev, unsigned int func,\n"
        "                           unsigned int bus);\n"
        "\n"
        "static int Get_Maximums(int x)\n"
        "{\n"
        "    return x;\n"
        "}\n"
        "\n"
        "static int Get_ConfigSpace(unsigned int *count, char *values,\n"
        "                           unsigned int dev, unsigned int func,\n"
        "                           unsigned int bus)\n"
        "{\n"
        "    return 0;\n"
        "}\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    # Single-line prototype (line 3) is skipped; the single-line definition
    # (line 9) is the one and only recorded site.
    assert sites["_Get_Maximums"] == [("src/driver/PCIResourceDriver.c", 9)]
    # Multi-line prototype (lines 5-7, terminating in ";" on a continuation
    # line) is skipped; the multi-line definition (lines 14-17, wrapped
    # parameters before the "{") is recorded at its first line, not the
    # prototype's line.
    assert sites["_Get_ConfigSpace"] == [("src/driver/PCIResourceDriver.c", 14)]


def test_source_sites_finds_c_function_defined_inside_implementation(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Bus.m").write_text(
        "@implementation FooBus (Private)\n"
        "\n"
        "- (void)someMethod\n"
        "{\n"
        "}\n"
        "\n"
        "BOOL getCardConfig(unsigned int csn)\n"
        "{\n"
        "    return YES;\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["_getCardConfig"] == [("src/driver/Bus.m", 7)]


def test_source_sites_skips_c_prototype_inside_implementation(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Bus.m").write_text(
        "@implementation FooBus (Private)\n"
        "\n"
        "BOOL getCardConfig(unsigned int csn, void *buffer, unsigned int *length);\n"
        "\n"
        "BOOL getCardConfig(unsigned int csn, void *buffer, unsigned int *length)\n"
        "{\n"
        "    return YES;\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["_getCardConfig"] == [("src/driver/Bus.m", 5)]


def test_source_sites_still_finds_methods_alongside_c_definition_in_same_block(
    tmp_path,
):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Bus.m").write_text(
        "@implementation FooBus (Private)\n"
        "\n"
        "BOOL getCardConfig(unsigned int csn)\n"
        "{\n"
        "    return YES;\n"
        "}\n"
        "\n"
        "- (void)someMethod\n"
        "{\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["_getCardConfig"] == [("src/driver/Bus.m", 3)]
    assert sites["-[FooBus(Private) someMethod]"] == [("src/driver/Bus.m", 8)]


def test_source_sites_finds_c_function_defined_after_implementation_end(tmp_path):
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Bus.m").write_text(
        "@implementation FooBus\n"
        "\n"
        "- (void)someMethod\n"
        "{\n"
        "}\n"
        "\n"
        "@end\n"
        "\n"
        "int helperAfterEnd(int x)\n"
        "{\n"
        "    return x;\n"
        "}\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["_helperAfterEnd"] == [("src/driver/Bus.m", 9)]


def test_source_sites_finds_kandr_definition_with_return_type_on_its_own_line(
    tmp_path,
):
    """K&R style: the return type is alone on one line; the name and
    parameter list start the next; each indented parameter declaration ends
    in ';' and must not be mistaken for the definition's own terminator.

    Known limitation, not fixed here: `kandr` is set from
    `line.rstrip().endswith(")")` on the header line itself. If the header's
    own parameter list instead wraps across multiple lines, `kandr` is never
    set, and the K&R parameter declarations that follow are misread as a
    prototype's ';' terminator, dropping the definition. Not exercised here
    - reproducing it would pin the bug, not the fix.
    """
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "bpf.c").write_text(
        "static int\n"
        "bpf_movein(uio, mp)\n"
        "\tstruct uio *uio;\n"
        "\tstruct mbuf **mp;\n"
        "{\n"
        "\treturn 0;\n"
        "}\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["_bpf_movein"] == [("src/driver/bpf.c", 2)]


def test_source_sites_finds_kandr_definition_with_unindented_parameters(tmp_path):
    """K&R parameter declarations need not be indented.

    drvSCSITape's stblocksize.c writes them at column zero. Each still ends
    in ';' and must not be read as a prototype's terminator just because it
    starts in column zero.
    """
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "stblocksize.c").write_text(
        "int\n"
        "do_ioc(srp)\n"
        "struct scsi_req *srp;\n"
        "{\n"
        "    return 0;\n"
        "}\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["_do_ioc"] == [("src/driver/stblocksize.c", 2)]


def test_source_sites_finds_ansi_definition_with_return_type_on_its_own_line(
    tmp_path,
):
    """Not K&R: a plain ANSI parameter list, but the return type is still
    wrapped onto its own line, which the old (mandatory-prefix) regex could
    not handle either."""
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "ide.c").write_text(
        "int\n"
        "ide_block_char_majors(int a, int b)\n"
        "{\n"
        "    return a + b;\n"
        "}\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["_ide_block_char_majors"] == [("src/driver/ide.c", 2)]


def test_source_sites_still_skips_forward_declaration_with_return_type_on_its_own_line(
    tmp_path,
):
    """A genuine prototype - ending in ';', no body - must still be rejected
    now that _C_DEFINITION's return-type prefix is optional. This is the
    property most at risk from that change: without this test, a scanner
    that recorded every parenthesized, ';'-terminated line as a definition
    would make the two tests above pass too, while badly over-reporting.
    """
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "ide.c").write_text(
        "int\n"
        "ide_block_char_majors(int a, int b);\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert "_ide_block_char_majors" not in sites


def test_source_sites_finds_semicolon_then_brace_method_definition(tmp_path):
    """NeXT-era GCC allows a ';' between a method signature and its body.

    AppleCuda's StartCudaTransmission: in cuda.m is written this way; the
    scanner used to read the trailing ';' as ending a forward declaration
    and never recorded a site for the definition that follows.
    """
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Cuda.m").write_text(
        "@implementation AppleCuda\n"
        "\n"
        "- (void)StartCudaTransmission:(CudaRequest *)plugInMessage;\n"
        "{\n"
        "    return;\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["-[AppleCuda StartCudaTransmission:]"] == [
        ("src/driver/Cuda.m", 3)
    ]


def test_source_sites_still_skips_bare_semicolon_method_declaration(tmp_path):
    """A signature ending in ';' with no following brace is a declaration,
    not a definition, and must remain ignored. This must not regress just
    because a brace-after-semicolon definition is now recorded."""
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Forward.m").write_text(
        "@implementation Foo\n"
        "\n"
        "- (void)declaredOnly:(int)x;\n"
        "\n"
        "- (void)realMethod\n"
        "{\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert "-[Foo declaredOnly:]" not in sites
    assert sites["-[Foo realMethod]"] == [("src/driver/Forward.m", 5)]


def test_source_sites_declaration_does_not_reach_a_later_c_function_brace(tmp_path):
    """Only the *next* non-blank line may turn a ';' into a definition.

    A forward declaration followed by something that is not a structural
    boundary but eventually opens a brace -- here a C helper -- must not be
    read as a definition. Scanning on until any brace both invents
    "-[Foo declaredOnly:]" and swallows the helper, because the outer loop
    resumes past it.
    """
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Helper.m").write_text(
        "@implementation Foo\n"
        "\n"
        "- (void)declaredOnly:(int)x;\n"
        "\n"
        "static int helper(int a) {\n"
        "    return a;\n"
        "}\n"
        "\n"
        "- (void)realMethod\n"
        "{\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert "-[Foo declaredOnly:]" not in sites
    assert sites["_helper"] == [("src/driver/Helper.m", 5)]
    assert sites["-[Foo realMethod]"] == [("src/driver/Helper.m", 9)]


def test_source_sites_ignores_a_c_continuation_line_starting_with_a_sign(tmp_path):
    """`_METHOD` matches any indented line starting with '-' or '+'.

    BMacEnetPrivate.m wraps arithmetic that way. The trailing ';' is what
    stops the body search; without it "+ 2 * sizeof(IODBDMADescriptor) );"
    scans on to the next brace and yields "+[Foo 2]".
    """
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Wrap.m").write_text(
        "@implementation Foo\n"
        "\n"
        "- (void)compute\n"
        "{\n"
        "    dbdmaSize = round_page( RX_RING_LENGTH * sizeof(enet_dma_cmd_t)\n"
        "                              + 2 * sizeof(IODBDMADescriptor) );\n"
        "    /*\n"
        "     * Allocate required memory\n"
        "     */\n"
        "    if ( !dmaCommands )\n"
        "    {\n"
        "        badFrameCount = ReadBigMacRegister(ioBaseEnet, kFECNT)\n"
        "                          + ReadBigMacRegister(ioBaseEnet, kAECNT)\n"
        "                              + ReadBigMacRegister(ioBaseEnet, kLECNT);\n"
        "    }\n"
        "}\n"
        "\n"
        "- (void)realMethod\n"
        "{\n"
        "}\n"
        "\n"
        "@end\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites == {
        "-[Foo compute]": [("src/driver/Wrap.m", 3)],
        "-[Foo realMethod]": [("src/driver/Wrap.m", 18)],
    }


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


def test_build_source_map_keeps_analysis_names_verbatim_but_resolves_via_symbol_table():
    analysis = _analysis([_function(0x2000, 0x10, ["sub_2000"])])
    macho = {
        "symbols": [
            {"name": "_helper", "address": 0x2000, "binding": "local", "section": "__text"}
        ]
    }

    document = build_source_map(analysis, macho, {"_helper": [("src/driver/x.c", 4)]})

    assert document["mapped"][0]["reference_names"] == ["sub_2000"]
    assert document["mapped"][0]["source_path"] == "src/driver/x.c"
    assert document["mapped"][0]["source_line"] == 4


def test_build_source_map_rejects_nameless_analysis_function():
    analysis = _analysis([_function(0x3000, 0x10, [])])
    macho = {"symbols": []}

    with pytest.raises(ValueError, match="has no names"):
        build_source_map(analysis, macho, {})


def _full_analysis(functions, sha256="A" * 64):
    return {
        "schema_version": "analysis-v1",
        "input": {
            "path": "build/drvPCIBus",
            "size": 0x40,
            "sha256": sha256,
            "architecture": "i386",
            "endianness": "little",
        },
        "analyzer": {
            "name": "fixture",
            "version": "1.0",
            "invocation": "fixture --analyze build/drvPCIBus",
        },
        "sections": [
            {
                "name": "__TEXT,__text",
                "address": 0x1000,
                "offset": 0,
                "size": 0x40,
                "permissions": "rx",
                "sha256": "B" * 64,
            }
        ],
        "symbols": [],
        "relocations": [],
        "functions": functions,
    }


def test_build_source_map_document_passes_the_semantic_validator(tmp_path):
    # The analysis names this function "sub_1000" (no symbol info recovered),
    # while the Mach-O symbol table has the real name "_realName" at the same
    # address. This divergence is what makes the test a real guard: the old
    # (pre-fix) build_source_map merged the two into reference_names, which
    # the semantic validator rejects because it must equal the analysis's
    # names exactly.
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Bus.m").write_text("\n" * 20, encoding="utf-8")

    analysis = _full_analysis([_function(0x1000, 0x10, ["sub_1000"])])
    macho = {
        "symbols": [
            {
                "name": "_realName",
                "address": 0x1000,
                "binding": "local",
                "section": "__TEXT,__text",
            }
        ]
    }
    sites = {"_realName": [("src/driver/Bus.m", 12)]}

    document = build_source_map(analysis, macho, sites)

    assert document["mapped"][0]["reference_names"] == ["sub_1000"]

    output_path = tmp_path / "source-map.json"
    output_path.write_text(json.dumps(document), encoding="utf-8")

    loaded = schema.load_source_map(
        output_path, reference_analysis=analysis, repo_root=tmp_path
    )

    assert loaded == document


def test_build_source_map_rejects_disputed_address_not_in_analysis():
    analysis = _analysis([_function(0x1000, 0x10, ["_known"])])
    macho = {"symbols": []}

    with pytest.raises(ValueError, match="disputed addresses"):
        build_source_map(analysis, macho, {}, disputed={0x9999})


def test_build_source_map_auto_disputes_overlapping_function_pair():
    # __PnPEntry (0x6fec, size 103, ends 0x704b) overlaps push_arg
    # (0x7024, size 6), the real drvEISABus case: push_arg is an interior
    # label inside the hand-written thunk, not a separate function.
    analysis = _analysis(
        [
            _function(0x6FEC, 103, ["__PnPEntry"]),
            _function(0x7024, 6, ["push_arg"]),
        ]
    )
    macho = {"symbols": []}

    document = build_source_map(analysis, macho, {})

    assert [entry["address"] for entry in document["boundary_disputed"]] == [
        0x6FEC,
        0x7024,
    ]
    for entry in document["boundary_disputed"]:
        assert entry["reasons"] == [
            "function range overlaps another; symbol may be an interior label"
        ]
    assert document["mapped"] == []
    assert document["unmapped"] == []
    assert document["duplicate_candidates"] == []


def test_build_source_map_auto_disputes_a_three_function_overlap_chain():
    # A overlaps B, and B overlaps C, but A does not overlap C directly.
    # Every function touched by any overlap must end up disputed.
    analysis = _analysis(
        [
            _function(0x1000, 0x20, ["_a"]),   # 0x1000..0x1020
            _function(0x1010, 0x20, ["_b"]),   # 0x1010..0x1030, overlaps _a
            _function(0x1028, 0x10, ["_c"]),   # 0x1028..0x1038, overlaps _b only
        ]
    )
    macho = {"symbols": []}

    document = build_source_map(analysis, macho, {})

    assert [entry["address"] for entry in document["boundary_disputed"]] == [
        0x1000,
        0x1010,
        0x1028,
    ]
    assert document["mapped"] == []
    assert document["unmapped"] == []
    assert document["duplicate_candidates"] == []


def test_build_source_map_composes_explicit_disputed_with_auto_detected_overlap():
    analysis = _analysis(
        [
            _function(0x1000, 0x10, ["_explicit"]),
            _function(0x2000, 0x10, ["_overlap_a"]),
            _function(0x2008, 0x10, ["_overlap_b"]),
        ]
    )
    macho = {"symbols": []}

    document = build_source_map(
        analysis, macho, {}, disputed={0x1000}
    )

    boundary_by_address = {
        entry["address"]: entry for entry in document["boundary_disputed"]
    }
    assert set(boundary_by_address) == {0x1000, 0x2000, 0x2008}
    assert boundary_by_address[0x1000]["reasons"] == [
        "analyzers disagree on function extent"
    ]
    assert boundary_by_address[0x2000]["reasons"] == [
        "function range overlaps another; symbol may be an interior label"
    ]
    assert boundary_by_address[0x2008]["reasons"] == [
        "function range overlaps another; symbol may be an interior label"
    ]


def test_build_source_map_leaves_non_overlapping_functions_unaffected():
    analysis = _analysis(
        [
            _function(0x1000, 0x10, ["-[PCIKernBus init]"]),
            _function(0x1010, 0x10, ["_PCIBus_VERS_NUM"]),
        ]
    )
    macho = {"symbols": []}
    sites = {"-[PCIKernBus init]": [("src/driver/Bus.m", 12)]}

    document = build_source_map(analysis, macho, sites)

    assert document["boundary_disputed"] == []
    assert [entry["address"] for entry in document["mapped"]] == [0x1000]
    assert [entry["address"] for entry in document["unmapped"]] == [0x1010]


def test_extra_names_resolve_a_source_site_the_symbol_table_cannot():
    analysis = _analysis([_function(0x2000, 0x10, ["sub_2000"])])
    macho = {"symbols": []}
    sites = {"-[Thing doThing]": [("src/thing.m", 12)]}

    document = build_source_map(
        analysis, macho, sites, extra_names={0x2000: ["-[Thing doThing]"]}
    )

    assert document["mapped"] == [
        {
            "address": 0x2000,
            "size": 0x10,
            "reference_names": ["sub_2000"],
            "source_path": "src/thing.m",
            "source_line": 12,
        }
    ]


def test_extra_names_are_merged_with_the_symbol_table_not_substituted_for_it():
    analysis = _analysis([_function(0x2000, 0x10, ["sub_2000"])])
    macho = {
        "symbols": [
            {"name": "_helper", "address": 0x2000, "binding": "local", "section": "__text"}
        ]
    }
    sites = {"_helper": [("src/thing.c", 3)], "-[Thing doThing]": [("src/thing.m", 12)]}

    document = build_source_map(
        analysis, macho, sites, extra_names={0x2000: ["-[Thing doThing]"]}
    )

    # Both names resolve to a site, so the address is genuinely ambiguous.
    assert [entry["address"] for entry in document["duplicate_candidates"]] == [0x2000]


def test_scope_analysis_keeps_only_the_named_addresses_and_the_identity():
    analysis = _analysis([
        {"address": 0x1000, "size": 8, "names": ["a"]},
        {"address": 0x2000, "size": 8, "names": ["b"]},
    ])

    scoped = scope_analysis(analysis, {0x2000})

    assert [f["address"] for f in scoped["functions"]] == [0x2000]
    assert scoped["input"] == analysis["input"]
    assert [f["address"] for f in analysis["functions"]] == [0x1000, 0x2000]


def test_source_sites_finds_a_definition_whose_return_type_is_on_its_own_line(tmp_path):
    """K&R style: the type sits alone and the name starts at column zero.

    NeXT and BSD sources use this widely -- drvAdaptec1542B's ahaTimeout is
    written this way -- and the reference binaries carry the symbol, so a
    scanner that only understood "static void foo(" reported it missing.
    """
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Thread.m").write_text(
        "static void ahaTimeout(void *arg);\n"
        "\n"
        "static void\n"
        "ahaTimeout(void *arg)\n"
        "{\n"
        "}\n"
        "\n"
        "int\n"
        "otherThing(void)\n"
        "{\n"
        "    ahaTimeout(0);\n"
        "    return 0;\n"
        "}\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["_ahaTimeout"] == [("src/driver/Thread.m", 4)]
    assert sites["_otherThing"] == [("src/driver/Thread.m", 9)]


def test_source_sites_does_not_treat_a_column_zero_call_as_a_definition(tmp_path):
    """The wrapped-form alternative must not match an ordinary call.

    A call at column zero inside a function body ends in a semicolon, and the
    scanner skips those before the pattern is tried; assert that directly so
    the guard cannot be removed silently.
    """
    source_dir = tmp_path / "src" / "driver"
    source_dir.mkdir(parents=True)
    (source_dir / "Call.m").write_text(
        "int\n"
        "realThing(void)\n"
        "{\n"
        "someCall(1);\n"
        "return 0;\n"
        "}\n",
        encoding="utf-8",
    )

    sites = source_sites(tmp_path, source_dir)

    assert sites["_realThing"] == [("src/driver/Call.m", 2)]
    assert "_someCall" not in sites
