from pathlib import Path

from symbol_name_check import hand_written_c_symbols, main, missing_definitions, source_definitions

REFERENCE_BINARY = Path(
    "C:/Users/raynorpat/Downloads/test/Drivers/ppc/PPCSerialPort.config/PPCSerialPort_reloc"
)
GNIC_REFERENCE_BINARY = Path(
    "C:/Users/raynorpat/Downloads/test/Drivers/ppc/drvPPCGNic.config/drvPPCGNic_reloc"
)
GNIC_SOURCE_DIR = Path("src/drivers-ppc/network/drvPPCGNic/GNic.drvproj/GNic.lksproj")


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
