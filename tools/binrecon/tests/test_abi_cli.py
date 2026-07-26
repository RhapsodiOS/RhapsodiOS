import json

from binrecon.objc_abi import attach_symbols


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
