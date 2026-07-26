import pytest

from binrecon.module_scope import function_ranges

TEXT = {"name": "__TEXT,__text", "address": 0x1000, "size": 0x100}
SYMBOLS = [
    {"name": "_alpha", "address": 0x1000, "section": "__TEXT,__text"},
    {"name": "_beta", "address": 0x1040, "section": "__TEXT,__text"},
    {"name": "_gamma", "address": 0x1080, "section": "__TEXT,__text"},
    {"name": "_data", "address": 0x2000, "section": "__DATA,__data"},
    {"name": "_undefined", "address": 0, "section": None},
]


def test_emits_one_range_per_named_function():
    assert function_ranges(SYMBOLS, TEXT, ["_alpha", "_gamma"]) == [
        {"start": 0x1000, "end": 0x1040},
        {"start": 0x1080, "end": 0x1100},
    ]


def test_ranges_are_sorted_regardless_of_request_order():
    assert function_ranges(SYMBOLS, TEXT, ["_gamma", "_alpha"])[0]["start"] == 0x1000


def test_a_symbol_outside_text_is_an_error():
    with pytest.raises(ValueError, match="_data"):
        function_ranges(SYMBOLS, TEXT, ["_data"])


def test_an_unknown_symbol_is_an_error():
    with pytest.raises(ValueError, match="_nope"):
        function_ranges(SYMBOLS, TEXT, ["_nope"])


ALIASED_SYMBOLS = [
    {"name": "_alpha", "address": 0x1000, "section": "__TEXT,__text"},
    {"name": "_alpha_alias", "address": 0x1000, "section": "__TEXT,__text"},
    {"name": "_beta", "address": 0x1040, "section": "__TEXT,__text"},
]


def test_aliased_symbols_share_the_same_non_empty_range():
    assert function_ranges(ALIASED_SYMBOLS, TEXT, ["_alpha"]) == function_ranges(
        ALIASED_SYMBOLS, TEXT, ["_alpha_alias"]
    ) == [{"start": 0x1000, "end": 0x1040}]


ALIASED_LAST_SYMBOLS = [
    {"name": "_alpha", "address": 0x1000, "section": "__TEXT,__text"},
    {"name": "_beta", "address": 0x1040, "section": "__TEXT,__text"},
    {"name": "_beta_alias", "address": 0x1040, "section": "__TEXT,__text"},
]


def test_alias_on_last_function_ends_at_end_of_text():
    assert function_ranges(ALIASED_LAST_SYMBOLS, TEXT, ["_beta"]) == [
        {"start": 0x1040, "end": 0x1100}
    ]
