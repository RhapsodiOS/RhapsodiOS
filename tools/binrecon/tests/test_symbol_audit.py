from binrecon.symbol_audit import unclaimed_text_symbols


DOCUMENT = {"symbols": [
    {"name": "_NSClaimed", "address": 0x1000, "binding": "external",
     "section": "__TEXT,__text"},
    {"name": "_NSOrphan", "address": 0x1040, "binding": "external",
     "section": "__TEXT,__text"},
    {"name": "_NSLocalHelper", "address": 0x1080, "binding": "local",
     "section": "__TEXT,__text"},
    {"name": "_NSConstant", "address": 0x2000, "binding": "external",
     "section": "__TEXT,__const"},
    {"name": "_NSImported", "address": 0, "binding": "external",
     "section": None},
    {"name": "-[NSThing doThing]", "address": 0x10C0, "binding": "external",
     "section": "__TEXT,__text"},
]}


def test_reports_only_unclaimed_external_text_functions():
    assignment = {"NSThing.m": ["_NSClaimed"]}

    assert unclaimed_text_symbols(DOCUMENT, assignment) == ["_NSOrphan"]


def test_everything_claimed_reports_nothing():
    assignment = {"NSThing.m": ["_NSClaimed", "_NSOrphan"]}

    assert unclaimed_text_symbols(DOCUMENT, assignment) == []


def test_claims_from_several_modules_are_all_honoured():
    assignment = {"A.m": ["_NSClaimed"], "B.m": ["_NSOrphan"]}

    assert unclaimed_text_symbols(DOCUMENT, assignment) == []
