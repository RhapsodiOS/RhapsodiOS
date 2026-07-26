from binrecon.abi_check import diff_abi, external_symbols


def _module(**overrides):
    document = {
        "schema_version": "abi-v1",
        "module": "NSThing.m",
        "classes": [{
            "name": "NSThing",
            "superclass": "NSObject",
            "instance_size": 12,
            "info": 1,
            "ivars": [{"name": "_count", "type": "I", "offset": 4}],
            "instance_methods": [{"selector": "count", "types": "I8@8:12"}],
            "class_methods": [],
        }],
        "categories": [],
        "text_symbols": ["_NSThingHelper"],
        "data_symbols": ["_NSThingZero"],
    }
    document.update(overrides)
    return document


def test_identical_documents_agree():
    assert diff_abi(_module(), _module()) == []


def test_reports_a_changed_ivar_offset():
    actual = _module()
    actual["classes"][0]["ivars"][0]["offset"] = 8

    assert diff_abi(_module(), actual) == [
        "NSThing._count: offset expected 4, actual 8"
    ]


def test_reports_a_changed_instance_size():
    actual = _module()
    actual["classes"][0]["instance_size"] = 16

    assert diff_abi(_module(), actual) == [
        "NSThing: instance_size expected 12, actual 16"
    ]


def test_reports_a_missing_selector():
    actual = _module()
    actual["classes"][0]["instance_methods"] = []

    assert diff_abi(_module(), actual) == ["NSThing: missing instance method -count"]


def test_reports_a_changed_type_encoding():
    actual = _module()
    actual["classes"][0]["instance_methods"][0]["types"] = "i8@8:12"

    assert diff_abi(_module(), actual) == [
        "NSThing.-count: types expected I8@8:12, actual i8@8:12"
    ]


def test_reports_a_missing_c_symbol():
    actual = _module(text_symbols=[], data_symbols=["_NSThingZero"])

    assert diff_abi(_module(), actual) == [
        "NSThing.m: missing exported symbol _NSThingHelper"
    ]


def test_reports_an_unexpected_c_symbol():
    actual = _module(text_symbols=["_NSThingHelper", "_NSThingSurprise"])

    assert diff_abi(_module(), actual) == [
        "NSThing.m: unexpected exported symbol _NSThingSurprise"
    ]


def test_symbols_may_move_between_text_and_data():
    """Section placement of a constant is codegen, not ABI."""
    actual = _module(text_symbols=["_NSThingHelper", "_NSThingZero"],
                     data_symbols=[])

    assert diff_abi(_module(), actual) == []


def test_external_symbols_ignores_local_and_undefined():
    document = {"symbols": [
        {"name": "_public", "address": 0x1000, "binding": "external",
         "section": "__TEXT,__text"},
        {"name": "_helper", "address": 0x1040, "binding": "local",
         "section": "__TEXT,__text"},
        {"name": "_imported", "address": 0, "binding": "external",
         "section": None},
    ]}

    assert external_symbols(document) == {"_public"}
