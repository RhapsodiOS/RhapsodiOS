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
