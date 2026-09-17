from pathlib import Path

from symbol_name_check import (
    build_generated_data_symbols,
    data_definitions,
    hand_written_c_symbols,
    hand_written_data_symbols,
    main,
    missing_definitions,
    source_definitions,
)

REFERENCE_BINARY = Path(
    "C:/Users/raynorpat/Downloads/test/Drivers/ppc/PPCSerialPort.config/PPCSerialPort_reloc"
)
GNIC_REFERENCE_BINARY = Path(
    "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCGNic.config/drvPPCGNic_reloc"
)
GNIC_SOURCE_DIR = (
    Path(__file__).parents[3] / "src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj"
)


def test_symbol_matches_when_source_drops_the_leading_underscore():
    assert missing_definitions(["_changeState"], {"changeState"}) == []


def test_symbol_is_missing_when_source_keeps_the_leading_underscore():
    assert missing_definitions(["_changeState"], {"_changeState"}) == ["_changeState"]


def test_symbol_is_missing_when_no_definition_exists():
    assert missing_definitions(["_activatePort"], {"changeState"}) == ["_activatePort"]


def test_compiler_runtime_helpers_are_not_reported():
    assert missing_definitions(["__udivdi3", "__umoddi3"], set()) == []


def test_objective_c_methods_are_not_reported():
    assert missing_definitions(["-[PPCSerialPort free]", "+[PPCSerialPort probe:]"], set()) == []


def test_source_definitions_finds_a_static_function(tmp_path):
    (tmp_path / "a.m").write_text("static void changeState(int x)\n{\n    return;\n}\n")
    assert "changeState" in source_definitions(tmp_path)


def test_source_definitions_ignores_a_prototype(tmp_path):
    (tmp_path / "a.m").write_text("extern void changeState(int x);\n")
    assert source_definitions(tmp_path) == set()


def test_source_definitions_finds_a_brace_on_the_next_line(tmp_path):
    (tmp_path / "a.m").write_text("unsigned int ReadGNicRegister(int base)\n{\n    return 0;\n}\n")
    assert "ReadGNicRegister" in source_definitions(tmp_path)


def test_hand_written_c_symbols_excludes_objc_and_compiler_runtime():
    document = {
        "symbols": [
            {"name": "_changeState", "section": "__TEXT,__text"},
            {"name": "__udivdi3", "section": "__TEXT,__text"},
            {"name": "-[PPCSerialPort free]", "section": "__TEXT,__text"},
            {"name": "_elsewhere", "section": "__DATA,__data"},
        ]
    }
    assert hand_written_c_symbols(document) == ["_changeState"]


def test_main_exits_0_when_every_symbol_has_a_definition():
    exit_code = main(["--binary", str(GNIC_REFERENCE_BINARY), "--source-dir", str(GNIC_SOURCE_DIR)])
    assert exit_code == 0


def test_main_exits_1_when_a_source_tree_has_no_definitions(tmp_path):
    empty_dir = tmp_path / "empty"
    empty_dir.mkdir()
    exit_code = main(["--binary", str(REFERENCE_BINARY), "--source-dir", str(empty_dir)])
    assert exit_code == 1


# -- data symbol checking -----------------------------------------------------


def test_hand_written_data_symbols_includes_data_bss_and_common():
    document = {
        "symbols": [
            {"name": "_FloppyState", "section": "__DATA,__data"},
            {"name": "_fd_block_major", "section": "__DATA,__bss"},
            {"name": "_slock", "section": "__DATA,__common"},
            {"name": "_changeState", "section": "__TEXT,__text"},
            {"name": "_elsewhere", "section": None},
        ]
    }
    assert hand_written_data_symbols(document) == [
        "_FloppyState", "_fd_block_major", "_slock",
    ]


def test_hand_written_data_symbols_excludes_objc_metadata():
    document = {
        "symbols": [
            {"name": "_OBJC_CLASS_NAME_Floppy", "section": "__OBJC,__class"},
            {"name": "_FloppyState", "section": "__DATA,__data"},
        ]
    }
    assert hand_written_data_symbols(document) == ["_FloppyState"]


def test_data_definitions_finds_a_scalar_definition(tmp_path):
    (tmp_path / "a.m").write_text("unsigned int FloppyState = 0;\n")
    assert "FloppyState" in data_definitions(tmp_path)


def test_data_definitions_finds_an_uninitialized_definition(tmp_path):
    (tmp_path / "a.m").write_text("DriveInfo fdDriveInfo;\n")
    assert "fdDriveInfo" in data_definitions(tmp_path)


def test_data_definitions_finds_an_array_definition(tmp_path):
    (tmp_path / "a.m").write_text("unsigned int ssi_1mb[12] = {\n    1, 2,\n};\n")
    assert "ssi_1mb" in data_definitions(tmp_path)


def test_data_definitions_ignores_an_extern_declaration(tmp_path):
    (tmp_path / "a.m").write_text("extern unsigned int FloppyState;\n")
    assert data_definitions(tmp_path) == set()


def test_data_definitions_ignores_a_function_definition(tmp_path):
    (tmp_path / "a.m").write_text("unsigned int foo(int x)\n{\n    return x;\n}\n")
    assert data_definitions(tmp_path) == set()


def test_data_definitions_ignores_only_headers(tmp_path):
    (tmp_path / "a.h").write_text("unsigned int FloppyState = 0;\n")
    assert data_definitions(tmp_path) == set()


def test_main_check_data_flag_reports_missing_data_symbol(tmp_path, monkeypatch):
    import symbol_name_check

    (tmp_path / "a.m").write_text("/* no globals here */\n")

    def fake_read_macho(path):
        return {
            "symbols": [
                {"name": "_FloppyState", "section": "__DATA,__data"},
            ]
        }

    monkeypatch.setattr(symbol_name_check, "read_macho", fake_read_macho)
    exit_code = main([
        "--binary", "unused", "--source-dir", str(tmp_path), "--check-data",
    ])
    assert exit_code == 1


def test_main_check_data_flag_passes_when_definition_present(tmp_path, monkeypatch):
    import symbol_name_check

    (tmp_path / "a.m").write_text("unsigned int FloppyState = 0;\n")

    def fake_read_macho(path):
        return {
            "symbols": [
                {"name": "_FloppyState", "section": "__DATA,__data"},
            ]
        }

    monkeypatch.setattr(symbol_name_check, "read_macho", fake_read_macho)
    exit_code = main([
        "--binary", "unused", "--source-dir", str(tmp_path), "--check-data",
    ])
    assert exit_code == 0


def test_data_definitions_ignores_a_typedef(tmp_path):
    """A typedef names a type, not storage; treating it as one would mask a real gap."""
    (tmp_path / "a.m").write_text("typedef struct foo_s FloppyState;\n")
    assert data_definitions(tmp_path) == set()


def test_data_definitions_only_matches_at_column_zero(tmp_path):
    """File-scope only: an indented line is a struct member or a function-scope static."""
    (tmp_path / "a.m").write_text("struct s {\n    unsigned int FloppyState;\n};\n")
    assert "FloppyState" not in data_definitions(tmp_path)


# -- build-generated and gcc-suffixed symbols ---------------------------------


def test_build_generated_data_symbols_named_by_the_kernel_server_selector():
    document = {
        "symbols": [
            {"name": "+[FloppyKernelServerInstance kernelServerInstance]",
             "section": "__TEXT,__text"},
            {"name": "_Floppy_instance", "section": "__DATA,__common"},
        ]
    }
    assert build_generated_data_symbols(document) == {"_Floppy_instance"}


def test_build_generated_data_symbols_is_empty_without_the_selector():
    document = {"symbols": [{"name": "_Floppy_instance", "section": "__DATA,__common"}]}
    assert build_generated_data_symbols(document) == set()


def test_hand_written_data_symbols_excludes_the_generated_instance():
    """CreateKLLDInstance.sh emits it, so source correctly never defines it."""
    document = {
        "symbols": [
            {"name": "+[FloppyKernelServerInstance kernelServerInstance]",
             "section": "__TEXT,__text"},
            {"name": "_Floppy_instance", "section": "__DATA,__common"},
            {"name": "_FloppyState", "section": "__DATA,__data"},
        ]
    }
    assert hand_written_data_symbols(document) == ["_FloppyState"]


def test_hand_written_data_symbols_excludes_gcc_suffixed_statics():
    """`_protocols.26` is a function-scope static; no file-scope name can spell it."""
    document = {
        "symbols": [
            {"name": "_protocols.26", "section": "__DATA,__data"},
            {"name": "_FloppyState", "section": "__DATA,__data"},
        ]
    }
    assert hand_written_data_symbols(document) == ["_FloppyState"]


def test_main_check_data_flag_prints_the_data_counts(tmp_path, monkeypatch, capsys):
    import symbol_name_check

    (tmp_path / "a.m").write_text("/* no globals here */\n")

    def fake_read_macho(path):
        return {"symbols": [{"name": "_FloppyState", "section": "__DATA,__data"}]}

    monkeypatch.setattr(symbol_name_check, "read_macho", fake_read_macho)
    main(["--binary", "unused", "--source-dir", str(tmp_path), "--check-data"])
    output = capsys.readouterr().out
    assert "hand-written data symbols: 1" in output
    assert "missing data definitions : 1" in output
    assert "  _FloppyState" in output


def test_main_check_data_flag_reports_a_text_miss_alongside_a_clean_data_side(
    tmp_path, monkeypatch
):
    """Exit is 1 on `missing or data_missing`, so a text-only miss still fails."""
    import symbol_name_check

    (tmp_path / "a.m").write_text("unsigned int FloppyState = 0;\n")

    def fake_read_macho(path):
        return {
            "symbols": [
                {"name": "_changeState", "section": "__TEXT,__text"},
                {"name": "_FloppyState", "section": "__DATA,__data"},
            ]
        }

    monkeypatch.setattr(symbol_name_check, "read_macho", fake_read_macho)
    exit_code = main([
        "--binary", "unused", "--source-dir", str(tmp_path), "--check-data",
    ])
    assert exit_code == 1


def test_main_without_check_data_flag_ignores_data_symbols(tmp_path, monkeypatch):
    """Callers that only want the text check keep their old, unaffected behavior."""
    import symbol_name_check

    (tmp_path / "a.m").write_text("/* no globals here */\n")

    def fake_read_macho(path):
        return {
            "symbols": [
                {"name": "_FloppyState", "section": "__DATA,__data"},
            ]
        }

    monkeypatch.setattr(symbol_name_check, "read_macho", fake_read_macho)
    exit_code = main(["--binary", "unused", "--source-dir", str(tmp_path)])
    assert exit_code == 0


# -- the name is read whole -----------------------------------------------------


def test_source_definitions_keeps_the_whole_name_after_a_same_line_return_type(tmp_path):
    """`void PCodeOpen(...)`: the return type is on the line, so the name is intact."""
    (tmp_path / "a.c").write_text("void PCodeOpen(int a)\n{\n}\n")
    assert source_definitions(tmp_path) == {"PCodeOpen"}


def test_source_definitions_keeps_the_first_character_of_a_column_zero_name(tmp_path):
    """`PCodeOpen(...)` under its return type once yielded `CodeOpen`: the leading
    `[A-Za-z_]` meant for the return type ate the name's first character."""
    (tmp_path / "a.c").write_text("OSStatus\nPCodeOpen(int a)\n{\n}\n")
    assert source_definitions(tmp_path) == {"PCodeOpen"}


def test_source_definitions_keeps_a_digit_bearing_column_zero_name(tmp_path):
    """`m64Init(...)` under its return type once yielded `Init`: the lazy type
    pattern matched empty and the name's `m64` was swallowed as the type."""
    (tmp_path / "a.c").write_text("void\nm64Init(volatile UInt32 *b)\n{\n}\n")
    assert source_definitions(tmp_path) == {"m64Init"}


def test_source_definitions_keeps_a_digit_bearing_name_after_a_same_line_type(tmp_path):
    (tmp_path / "a.c").write_text("void m64Init(volatile UInt32 *b)\n{\n}\n")
    assert source_definitions(tmp_path) == {"m64Init"}


def test_source_definitions_keeps_a_leading_underscore_in_the_source_name(tmp_path):
    """`_m64Init` is what the source spells, so that is what the scanner records;
    the over-underscored symbol it produces is a real gap, not a scanner miss."""
    (tmp_path / "a.c").write_text("static void _m64Init(volatile UInt32 *b)\n{\n}\n")
    assert source_definitions(tmp_path) == {"_m64Init"}


def test_source_definitions_ignores_a_column_zero_call_with_no_return_type_above(tmp_path):
    """A bare `name(args)` at column 0 is a definition only when a return type
    sits above it; otherwise it is a function-like macro invocation."""
    (tmp_path / "a.c").write_text(
        "/* a table built by a macro, not a function */\n"
        "DEFINE_TABLE(entries)\n"
        "{\n"
        "    1, 2,\n"
        "};\n"
    )
    assert source_definitions(tmp_path) == set()


def test_source_definitions_ignores_a_column_zero_call_under_a_closing_brace(tmp_path):
    """A closing brace is not a return type, so the line below it is not a definition."""
    (tmp_path / "a.c").write_text("void done(void)\n{\n}\n\nINVOKE_MACRO(x)\n{\n}\n")
    assert source_definitions(tmp_path) == {"done"}


# -- the body brace is found past a multi-line parameter list -------------------


def test_source_definitions_finds_a_brace_past_a_multi_line_parameter_list(tmp_path):
    """PEF_OpenContainer's parameter list spans ten lines, pushing its `{` well
    past the four-line window the scanner used to look through."""
    (tmp_path / "a.c").write_text(
        "OSStatus    PEF_OpenContainer   ( LogicalAddress            mappedAddress,\n"
        "                                  LogicalAddress            runningAddress,\n"
        "                                  ByteCount                 containerLength,\n"
        "                                  KernelProcessID           runningProcessID,\n"
        "                                  const CFContHashedName *  cfragName,\n"
        "                                  CFContOpenOptions         options,\n"
        "                                  CFContAllocateMem         Allocate,\n"
        "                                  CFContReleaseMem          Release,\n"
        "                                  CFContHandlerRef *        containerRef,\n"
        "                                  CFContHandlerProcsPtr *   handlerProcs )\n"
        "{\n"
        "    return -1;\n"
        "}\n"
    )
    assert source_definitions(tmp_path) == {"PEF_OpenContainer"}


def test_source_definitions_ignores_a_multi_line_prototype(tmp_path):
    """The widened window must still reject a prototype: the `;` arrives first."""
    (tmp_path / "a.c").write_text(
        "extern OSStatus PEF_OpenContainer( LogicalAddress   mappedAddress,\n"
        "                                   LogicalAddress   runningAddress,\n"
        "                                   ByteCount        containerLength,\n"
        "                                   CFContOpenOptions options,\n"
        "                                   CFContAllocateMem Allocate );\n"
        "\n"
        "void other(void)\n"
        "{\n"
        "}\n"
    )
    assert source_definitions(tmp_path) == {"other"}


def test_source_definitions_ignores_a_prototype_followed_by_a_definition(tmp_path):
    """A prototype whose `;` precedes a later `{` must not borrow that brace."""
    (tmp_path / "a.c").write_text(
        "static void changeState(int x);\n"
        "\n"
        "static void other(int x)\n"
        "{\n"
        "}\n"
    )
    assert source_definitions(tmp_path) == {"other"}


def test_source_definitions_ignores_a_column_zero_prototype_under_its_return_type(tmp_path):
    """Return type above, name at column 0, but a `;` ends it: still a prototype."""
    (tmp_path / "a.c").write_text("OSStatus\nPCodeOpen( int a );\n")
    assert source_definitions(tmp_path) == set()
