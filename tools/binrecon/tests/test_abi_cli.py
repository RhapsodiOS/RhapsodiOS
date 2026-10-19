from binrecon.cli import _filter_assignment_to_requested_modules
from binrecon.objc_abi import attach_symbols
from binrecon.schema import validate_document


def test_attaches_symbols_by_declared_assignment():
    modules = {"NSRange.m": {
        "schema_version": "abi-v1", "module": "NSRange.m",
        "classes": [], "categories": [],
        "text_symbols": [], "data_symbols": [],
    }}
    symbols = [
        {"name": "_NSUnionRange", "address": 0x1000, "section": "__TEXT,__text"},
        {"name": "_NSZeroRect", "address": 0x2000, "section": "__DATA,__data"},
        {"name": "_NSStringFromRect", "address": 0x1040, "section": "__TEXT,__text"},
        {"name": "_undefined", "address": 0, "section": None},
    ]

    attach_symbols(modules, {"NSRange.m": ["_NSUnionRange", "_NSZeroRect"]}, symbols)

    assert modules["NSRange.m"]["text_symbols"] == ["_NSUnionRange"]
    assert modules["NSRange.m"]["data_symbols"] == ["_NSZeroRect"]


def test_text_const_section_is_classified_as_data():
    modules = {"NSGeometry.m": {
        "schema_version": "abi-v1", "module": "NSGeometry.m",
        "classes": [], "categories": [],
        "text_symbols": [], "data_symbols": [],
    }}
    symbols = [
        {"name": "_NSZeroPoint", "address": 0x3000, "section": "__TEXT,__const"},
    ]

    attach_symbols(modules, {"NSGeometry.m": ["_NSZeroPoint"]}, symbols)

    assert modules["NSGeometry.m"]["text_symbols"] == []
    assert modules["NSGeometry.m"]["data_symbols"] == ["_NSZeroPoint"]


def test_unknown_symbol_is_an_error():
    import pytest
    from binrecon.objc_abi import ObjcAbiError

    modules = {"NSRange.m": {
        "schema_version": "abi-v1", "module": "NSRange.m",
        "classes": [], "categories": [],
        "text_symbols": [], "data_symbols": [],
    }}
    with pytest.raises(ObjcAbiError, match="_NSNope"):
        attach_symbols(modules, {"NSRange.m": ["_NSNope"]}, [])


def test_assignment_naming_unknown_module_is_an_error():
    import pytest
    from binrecon.objc_abi import ObjcAbiError

    modules = {"NSRange.m": {
        "schema_version": "abi-v1", "module": "NSRange.m",
        "classes": [], "categories": [],
        "text_symbols": [], "data_symbols": [],
    }}
    symbols = [
        {"name": "_NSUnionRange", "address": 0x1000, "section": "__TEXT,__text"},
    ]
    with pytest.raises(ObjcAbiError, match="NSGeometry.m"):
        attach_symbols(
            modules, {"NSGeometry.m": ["_NSUnionRange"]}, symbols
        )


def test_undefined_symbol_is_an_error():
    import pytest
    from binrecon.objc_abi import ObjcAbiError

    modules = {"NSRange.m": {
        "schema_version": "abi-v1", "module": "NSRange.m",
        "classes": [], "categories": [],
        "text_symbols": [], "data_symbols": [],
    }}
    symbols = [
        {"name": "_undefined", "address": 0, "section": None},
    ]
    with pytest.raises(ObjcAbiError, match="_undefined"):
        attach_symbols(modules, {"NSRange.m": ["_undefined"]}, symbols)


def test_emitted_document_validates_against_abi_v1():
    modules = {"NSRange.m": {
        "schema_version": "abi-v1", "module": "NSRange.m",
        "classes": [{
            "name": "NSValue",
            "superclass": "Object",
            "instance_size": 8,
            "info": 0,
            "ivars": [{"name": "_range", "type": "{_NSRange=II}", "offset": 4}],
            "instance_methods": [{"selector": "rangeValue", "types": "{_NSRange=II}8@0:4"}],
            "class_methods": [],
        }],
        "categories": [],
        "text_symbols": [], "data_symbols": [],
    }}
    symbols = [
        {"name": "_NSUnionRange", "address": 0x1000, "section": "__TEXT,__text"},
        {"name": "_NSZeroRect", "address": 0x2000, "section": "__DATA,__data"},
    ]

    attach_symbols(modules, {"NSRange.m": ["_NSUnionRange", "_NSZeroRect"]}, symbols)

    validate_document("abi-v1", modules["NSRange.m"])


def test_filtered_assignment_still_errors_for_a_requested_module_the_image_lacks():
    import pytest
    from binrecon.objc_abi import ObjcAbiError

    modules = {"NSRange.m": {
        "schema_version": "abi-v1", "module": "NSRange.m",
        "classes": [], "categories": [],
        "text_symbols": [], "data_symbols": [],
    }}
    symbols = [
        {"name": "_NSUnionRange", "address": 0x1000, "section": "__TEXT,__text"},
    ]
    assignment = {"NSGeometry.m": ["_NSUnionRange"]}
    requested_modules = ["NSGeometry.m"]

    filtered = _filter_assignment_to_requested_modules(
        assignment, requested_modules, modules)

    with pytest.raises(ObjcAbiError, match="NSGeometry.m"):
        attach_symbols(modules, filtered, symbols)


def test_filtered_assignment_ignores_a_module_not_requested():
    modules = {"NSRange.m": {
        "schema_version": "abi-v1", "module": "NSRange.m",
        "classes": [], "categories": [],
        "text_symbols": [], "data_symbols": [],
    }}
    symbols = [
        {"name": "_NSUnionRange", "address": 0x1000, "section": "__TEXT,__text"},
    ]
    # NSZone.m is not a module the image defines (and is not requested here);
    # its presence in the assignment must not raise once filtered.
    assignment = {
        "NSRange.m": ["_NSUnionRange"],
        "NSZone.m": ["_NSZoneMalloc"],
    }
    requested_modules = ["NSRange.m"]

    filtered = _filter_assignment_to_requested_modules(
        assignment, requested_modules, modules)

    attach_symbols(modules, filtered, symbols)

    assert modules["NSRange.m"]["text_symbols"] == ["_NSUnionRange"]


def test_filtered_assignment_reports_every_key_it_drops(capsys):
    """A dropped key must never be silent.

    Dropping quietly is what lets a misspelled key reach the emitted document
    as an empty ``text_symbols``, which later reads as an unexplained
    unexpected-export finding rather than as missing evidence.
    """
    modules = {
        name: {
            "schema_version": "abi-v1", "module": name,
            "classes": [], "categories": [],
            "text_symbols": [], "data_symbols": [],
        }
        for name in ("NSRange.m", "NSGeometry.m")
    }
    assignment = {
        "NSRange.m": ["_NSUnionRange"],
        "NSGeometry.m": ["_NSZeroRect"],
        "NSZone.m": ["_NSZoneMalloc"],
    }

    _filter_assignment_to_requested_modules(assignment, ["NSRange.m"], modules)

    reported = capsys.readouterr().err
    assert "NSGeometry.m (defined by the image)" in reported
    assert "NSZone.m (not an __OBJC module)" in reported
    assert "NSRange.m" not in reported
