import json
from pathlib import Path

import pytest

from binrecon.functions import (
    FunctionQueryError, differing_count, function_index, instruction_pairs,
    load_published, render_worklist, worklist,
)


def _function(name, mnemonics, address=0x1000):
    return {
        "address": address,
        "size": len(mnemonics) * 2,
        "names": [name],
        "blocks": [],
        "calls": [],
        "confidence": 1.0,
        "instructions": [
            {"address": address + index * 2, "bytes": "90", "mnemonic": mnemonic,
             "operands": "", "normalized_operands": operands, "relocations": []}
            for index, (mnemonic, operands) in enumerate(mnemonics)
        ],
    }


def _analysis(functions):
    return {"schema_version": "analysis-v1", "functions": functions}


def _comparison(rows):
    return {"functions": rows}


def test_function_index_maps_every_alias():
    fn = _function("one", [("push", "ebp")])
    fn["names"].append("also_one")

    index = function_index(_analysis([fn]))

    assert index["one"] is fn
    assert index["also_one"] is fn


def test_instruction_pairs_uses_mnemonic_and_normalized_operands():
    fn = _function("f", [("mov", "eax, ebx"), ("ret", "")])

    assert instruction_pairs(fn) == [("mov", "eax, ebx"), ("ret", "")]


def test_differing_count_is_zero_for_identical_sequences():
    left = _function("f", [("push", "ebp"), ("ret", "")])
    right = _function("f", [("push", "ebp"), ("ret", "")], address=0x2000)

    assert differing_count(left, right) == 0


def test_differing_count_counts_only_changed_instructions():
    left = _function("f", [("push", "ebp"), ("mov", "eax, 1"), ("ret", "")])
    right = _function("f", [("push", "ebp"), ("mov", "eax, 2"), ("ret", "")])

    assert differing_count(left, right) == 1


def test_differing_count_is_none_when_a_side_is_missing():
    assert differing_count(_function("f", [("ret", "")]), None) is None
    assert differing_count(None, _function("f", [("ret", "")])) is None


def test_worklist_sorts_by_differing_count_ascending_with_unpaired_last():
    reference = _analysis([
        _function("far", [("a", ""), ("b", ""), ("c", "")]),
        _function("near", [("a", ""), ("b", "")]),
        _function("gone", [("a", "")]),
    ])
    rebuilt = _analysis([
        _function("far", [("x", ""), ("y", ""), ("z", "")]),
        _function("near", [("a", ""), ("q", "")]),
    ])
    comparison = _comparison([
        {"status": "different", "reference_aliases": ["far"], "rebuilt_aliases": ["far"],
         "raw_equal": False, "masked_equal": False, "reasons": ["instruction shape differs"]},
        {"status": "different", "reference_aliases": ["near"], "rebuilt_aliases": ["near"],
         "raw_equal": False, "masked_equal": False, "reasons": ["instruction shape differs"]},
        {"status": "missing-rebuilt", "reference_aliases": ["gone"], "rebuilt_aliases": [],
         "raw_equal": False, "masked_equal": False, "reasons": ["missing rebuilt function"]},
    ])

    rows = worklist(reference, rebuilt, comparison)

    assert [row["name"] for row in rows] == ["near", "far", "gone"]
    assert rows[0]["differing"] == 1
    assert rows[1]["differing"] == 3
    assert rows[2]["differing"] is None


def test_worklist_reports_instruction_counts_and_equality_flags():
    reference = _analysis([_function("f", [("a", ""), ("b", "")])])
    rebuilt = _analysis([_function("f", [("a", ""), ("b", "")])])
    comparison = _comparison([
        {"status": "different", "reference_aliases": ["f"], "rebuilt_aliases": ["f"],
         "raw_equal": True, "masked_equal": True, "reasons": ["cfg differs"]},
    ])

    row = worklist(reference, rebuilt, comparison)[0]

    assert row["raw_equal"] is True
    assert row["reference_instructions"] == 2
    assert row["rebuilt_instructions"] == 2
    assert row["differing"] == 0


def test_render_worklist_marks_byte_identical_rows():
    rows = [
        {"name": "same", "status": "different", "raw_equal": True, "masked_equal": True,
         "differing": 0, "reference_instructions": 2, "rebuilt_instructions": 2,
         "reasons": ["cfg differs"]},
        {"name": "other", "status": "different", "raw_equal": False, "masked_equal": False,
         "differing": 4, "reference_instructions": 9, "rebuilt_instructions": 9,
         "reasons": ["instruction shape differs"]},
    ]

    text = render_worklist(rows)

    assert "same" in text and "other" in text
    assert "identical" in text
    assert text.index("same") < text.index("other")


def test_load_published_reports_a_missing_directory_by_path(tmp_path):
    with pytest.raises(FunctionQueryError) as error:
        load_published(tmp_path / "nowhere", "ida")

    assert str(tmp_path / "nowhere") in str(error.value)


def test_render_function_marks_differing_rows_and_keeps_equal_ones_unmarked():
    from binrecon.functions import render_function

    left = _function("f", [("push", "ebp"), ("mov", "eax, 1"), ("ret", "")])
    right = _function("f", [("push", "ebp"), ("mov", "eax, 2"), ("ret", "")])
    record = {"status": "different", "raw_equal": False, "masked_equal": False,
              "reasons": ["instruction shape differs"]}

    text = render_function("f", left, right, record)

    lines = [line for line in text.splitlines() if "mov" in line]
    assert lines and all(line.startswith("*") for line in lines)
    assert any(line.startswith(" ") and "push" in line for line in text.splitlines())
    assert "eax, 1" in text and "eax, 2" in text


def test_render_function_shows_the_verdict_and_reasons():
    from binrecon.functions import render_function

    fn = _function("f", [("ret", "")])
    record = {"status": "different", "raw_equal": True, "masked_equal": True,
              "reasons": ["cfg differs"]}

    text = render_function("f", fn, fn, record)

    assert "raw_equal=True" in text
    assert "cfg differs" in text


def test_render_function_handles_a_missing_side():
    from binrecon.functions import render_function

    fn = _function("f", [("ret", "")])
    record = {"status": "missing-rebuilt", "raw_equal": False, "masked_equal": False,
              "reasons": ["missing rebuilt function"]}

    text = render_function("f", fn, None, record)

    assert "missing" in text
    assert "ret" in text


def test_render_function_rejects_an_unknown_name():
    from binrecon.functions import FunctionQueryError, render_function

    with pytest.raises(FunctionQueryError) as error:
        render_function("nope", None, None, None)

    assert "nope" in str(error.value)


def test_parser_accepts_function_list_and_name():
    from binrecon.cli import build_parser

    listed = build_parser().parse_args(["function", "--profile", "p.json", "--list"])
    named = build_parser().parse_args(["function", "--profile", "p.json", "--name", "f"])

    assert listed.list_functions is True and listed.name is None
    assert named.list_functions is False and named.name == "f"
    assert listed.analyzer == "ida"


def test_help_lists_the_function_command():
    from binrecon.cli import build_parser

    assert "function" in build_parser().format_help()
