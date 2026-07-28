from symbol_name_check import missing_definitions, source_definitions


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
