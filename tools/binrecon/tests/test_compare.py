from copy import deepcopy
import hashlib
import json

import pytest

from binrecon.compare import ComparisonError, compare_artifacts, validate_comparison_report
from test_normalize import analysis


def _case(tmp_path, reference=b"\xe8\x78\x56\x34\x12\x3d\x78\x56\x34\x12\xe4\x80" + b"\0" * 52,
          rebuilt=None):
    if rebuilt is None:
        rebuilt = reference
    rp, bp = tmp_path / "reference.bin", tmp_path / "rebuilt.bin"
    rp.write_bytes(reference); bp.write_bytes(rebuilt)
    left, right = analysis("IDA"), analysis("Ghidra")
    for document, path, data in ((left, rp, reference), (right, bp, rebuilt)):
        document["input"].update(path=str(path), size=len(data),
                                 sha256=hashlib.sha256(data).hexdigest())
        document["sections"][0].update(size=len(data),
            sha256=hashlib.sha256(data).hexdigest())
    return rp, bp, left, right


def test_identical_artifacts_pass_every_acceptance_level(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    validate_comparison_report(report)
    assert report["acceptance"] == {
        "normalized-functions": True, "exact-sections": True, "exact-image": True}
    assert report["selected"] == {"requirement": "exact-image", "passed": True}
    assert all(not evidence for evidence in report["categories"].values())
    assert report["functions"][0]["status"] == "assembly-matched"


def test_relocation_field_difference_is_not_code_difference(tmp_path):
    original = b"\xe8\x78\x56\x34\x12\x3d\x78\x56\x34\x12\xe4\x80" + b"\0" * 52
    rebuilt = bytearray(original); rebuilt[1:5] = b"\x11\x22\x33\x44"
    rp, bp, left, right = _case(tmp_path, original, bytes(rebuilt))
    right["functions"][0]["instructions"][0]["bytes"] = "E811223344"
    right["sections"][0]["sha256"] = hashlib.sha256(rebuilt).hexdigest()
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["functions"][0]["status"] == "assembly-matched"
    assert report["acceptance"]["normalized-functions"] is True
    assert report["categories"]["relocation"]
    assert not report["categories"]["code"]


@pytest.mark.parametrize("mutation", [
    (5, "3C78563412"),       # opcode
    (6, "3D79563412"),       # literal constant
    (10, "E481"),            # port constant
])
def test_literal_opcode_and_port_changes_are_code(tmp_path, mutation):
    rp, bp, left, right = _case(tmp_path)
    index = 1 if mutation[0] < 10 else 2
    right["functions"][0]["instructions"][index]["bytes"] = mutation[1]
    right["functions"][0]["instructions"][index]["normalized_operands"] += " changed"
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert not report["acceptance"]["normalized-functions"]
    assert report["categories"]["code"]


def test_cfg_difference_and_missing_function_are_never_majority_matched(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    right["functions"][0]["blocks"][0]["successors"] = []
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["functions"][0]["status"] == "different"
    assert any(item["reason"] == "cfg differs" for item in report["categories"]["code"])
    right["functions"] = []
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["functions"][0]["status"] == "missing-rebuilt"


def test_section_layout_padding_and_content_are_distinct(tmp_path):
    data = b"HEAD" + b"CODE" + b"PAD!"
    rp, bp, left, right = _case(tmp_path, data, data)
    for doc in (left, right):
        doc["sections"] = [{"name": ".text", "address": 0x1000, "offset": 4,
                            "size": 4, "permissions": "rx",
                            "sha256": hashlib.sha256(b"CODE").hexdigest()}]
        doc["functions"] = []; doc["symbols"] = []; doc["relocations"] = []
        doc["references"] = []; doc["extensions"] = {}
    changed = bytearray(data); changed[-1] = ord("?")
    bp.write_bytes(changed); right["input"].update(size=len(changed), sha256=hashlib.sha256(changed).hexdigest())
    report = compare_artifacts(rp, bp, left, right, "exact-sections")
    assert report["acceptance"]["exact-sections"] is True
    assert report["acceptance"]["exact-image"] is False
    assert report["categories"]["padding"]
    right["sections"][0]["offset"] = 3
    report = compare_artifacts(rp, bp, left, right, "exact-sections")
    assert not report["acceptance"]["exact-sections"]
    assert report["categories"]["layout"]


def test_symbol_order_is_distinguished_from_content_and_metadata_ignore(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    left["symbols"].append({"name": "other", "address": 0x1030,
                            "binding": "local", "section": ".text"})
    right["symbols"] = deepcopy(list(reversed(left["symbols"])))
    right["analyzer"]["version"] = "different"
    report = compare_artifacts(rp, bp, left, right, "exact-image",
                                   ignore_metadata=["/analyzer/version"])
    assert report["categories"]["symbol-string-order"]
    assert not report["categories"]["metadata"]
    right["symbols"][0]["name"] = "changed"
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    assert any(item["reason"] == "symbols differ" for item in report["categories"]["metadata"])


def test_analysis_identity_must_match_opened_artifact(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    left["input"]["sha256"] = "0" * 64
    with pytest.raises(ComparisonError, match="analysis identity"):
        compare_artifacts(rp, bp, left, right, "exact-image")


def test_report_validator_rejects_open_or_incoherent_documents(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    report["unexpected"] = True
    with pytest.raises(ComparisonError): validate_comparison_report(report)
    del report["unexpected"]
    report["selected"]["passed"] = False
    with pytest.raises(ComparisonError): validate_comparison_report(report)
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    report["functions"][0]["extra"] = 1
    with pytest.raises(ComparisonError): validate_comparison_report(report)


def test_report_is_deterministic_under_analysis_collection_permutations(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    baseline = compare_artifacts(rp, bp, left, right, "normalized-functions")
    left["symbols"].reverse(); right["symbols"].reverse()
    assert compare_artifacts(rp, bp, left, right, "normalized-functions") == baseline


def test_zero_fill_is_compared_logically_without_file_range_or_allocation(tmp_path):
    rp, bp, left, right = _case(tmp_path, b"HEAD", b"HEAD")
    zero_hash = hashlib.sha256(b"\0" * 32).hexdigest()
    for document in (left, right):
        document["sections"] = [{"name": ".bss", "address": 0x2000, "offset": 999,
                                 "size": 32, "permissions": "rw", "sha256": zero_hash}]
        document["functions"] = []; document["symbols"] = []; document["relocations"] = []
        document["references"] = []
        document["extensions"] = {"macho": {"sections": [
            {"name": ".bss", "segment": "__DATA", "address": 0x2000, "offset": 999,
             "size": 32, "ordinal": 1, "alignment_exponent": 2, "alignment": 4,
             "flags": 1, "type": 1, "zero_fill": True, "initialized": False}]}}
    report = compare_artifacts(rp, bp, left, right, "exact-sections")
    assert report["acceptance"]["exact-sections"] is True


def _ghidra_fallback_zero_fill_case(tmp_path):
    artifact = b"HEAD" + b"\0" * 49
    rp, bp, left, right = _case(tmp_path, artifact, artifact)
    sections = [
        {"name": "__TEXT,__text", "address": 0x1000, "offset": 0, "size": 4,
         "permissions": "r-x", "sha256": hashlib.sha256(b"HEAD").hexdigest()},
        {"name": "__DATA,__bss", "address": 0x8100, "offset": 0, "size": 53,
         "permissions": "rw-", "sha256": hashlib.sha256(b"\0" * 53).hexdigest()},
        {"name": "__DATA,__common", "address": 0x8138, "offset": 0, "size": 4,
         "permissions": "rw-", "sha256": hashlib.sha256(b"\0" * 4).hexdigest()},
    ]
    metadata = [
        {**section, "ordinal": ordinal, "alignment": 4,
         "zero_fill": ordinal != 1, "initialized": ordinal == 1}
        for ordinal, section in enumerate(sections, 1)
    ]
    for document in (left, right):
        document["analyzer"]["name"] = "Ghidra"
        document["sections"] = deepcopy(sections)
        document["functions"] = []; document["symbols"] = []; document["relocations"] = []
        document["references"] = []
        document["extensions"] = {"ghidra": {"fallback_sections": deepcopy(metadata)}}
    return rp, bp, left, right


def test_ghidra_fallback_zero_fill_sections_do_not_create_file_overlap(tmp_path):
    rp, bp, left, right = _ghidra_fallback_zero_fill_case(tmp_path)

    report = compare_artifacts(rp, bp, left, right, "exact-sections")

    assert report["acceptance"]["exact-sections"] is True
    assert [section["reference"]["backing"] for section in report["sections"]] == [
        "file", "zero-fill", "zero-fill"]


def test_ida_zero_fill_and_external_sections_use_declared_backing(tmp_path):
    rp, bp, left, right = _ghidra_fallback_zero_fill_case(tmp_path)
    for document in (left, right):
        fallback = document["extensions"].pop("ghidra")["fallback_sections"]
        document["analyzer"]["name"] = "IDA"
        document["extensions"]["ida"] = {"sections": [
            {key: item[key] for key in
             ("name", "address", "offset", "size", "zero_fill", "initialized")}
            for item in fallback
        ]}

    report = compare_artifacts(rp, bp, left, right, "exact-sections")

    assert report["acceptance"]["exact-sections"] is True
    assert [section["reference"]["backing"] for section in report["sections"]] == [
        "file", "zero-fill", "zero-fill"]


@pytest.mark.parametrize("mutation", ["duplicate", "conflicting-flags"])
def test_ghidra_fallback_section_metadata_fails_closed_when_ambiguous(tmp_path, mutation):
    rp, bp, left, right = _ghidra_fallback_zero_fill_case(tmp_path)
    if mutation == "duplicate":
        left["extensions"]["ghidra"]["fallback_sections"].append(
            deepcopy(left["extensions"]["ghidra"]["fallback_sections"][1]))
    else:
        left["extensions"]["ghidra"]["fallback_sections"][1]["initialized"] = True

    with pytest.raises(ComparisonError, match="section backing metadata"):
        compare_artifacts(rp, bp, left, right, "exact-sections")


def test_ghidra_initialized_sections_still_reject_file_overlap(tmp_path):
    rp, bp, left, right = _ghidra_fallback_zero_fill_case(tmp_path)
    for document in (left, right):
        for metadata in document["extensions"]["ghidra"]["fallback_sections"][1:]:
            metadata.update(zero_fill=False, initialized=True)

    with pytest.raises(ComparisonError, match="file-backed sections overlap"):
        compare_artifacts(rp, bp, left, right, "exact-sections")


def _use_angr_loader_backing(document):
    fallback = document["extensions"].pop("ghidra")["fallback_sections"]
    document["analyzer"]["name"] = "angr"
    document["extensions"]["angr"] = {"loader": {"sections": [
        {key: item[key] for key in ("address", "size", "permissions", "initialized")}
        for item in fallback
    ]}}


def test_angr_loader_zero_fill_sections_do_not_create_file_overlap(tmp_path):
    rp, bp, left, right = _ghidra_fallback_zero_fill_case(tmp_path)
    for document in (left, right):
        _use_angr_loader_backing(document)

    report = compare_artifacts(rp, bp, left, right, "exact-sections")

    assert report["acceptance"]["exact-sections"] is True
    assert [section["reference"]["backing"] for section in report["sections"]] == [
        "file", "zero-fill", "zero-fill"]


def test_angr_loader_section_metadata_matches_unsorted_regions_by_identity(tmp_path):
    rp, bp, left, right = _ghidra_fallback_zero_fill_case(tmp_path)
    for document in (left, right):
        _use_angr_loader_backing(document)
        document["extensions"]["angr"]["loader"]["sections"].reverse()

    report = compare_artifacts(rp, bp, left, right, "exact-sections")

    assert report["acceptance"]["exact-sections"] is True
    assert [section["reference"]["backing"] for section in report["sections"]] == [
        "file", "zero-fill", "zero-fill"]


@pytest.mark.parametrize("mutation", ["duplicate", "missing"])
def test_angr_loader_section_metadata_fails_closed_on_count_mismatch(tmp_path, mutation):
    rp, bp, left, right = _ghidra_fallback_zero_fill_case(tmp_path)
    for document in (left, right):
        _use_angr_loader_backing(document)
    entries = left["extensions"]["angr"]["loader"]["sections"]
    if mutation == "duplicate":
        entries.append(deepcopy(entries[0]))
    else:
        entries.pop()

    with pytest.raises(ComparisonError, match="section backing metadata"):
        compare_artifacts(rp, bp, left, right, "exact-sections")


def test_angr_loader_repeated_identity_rejects_conflicting_initialization(tmp_path):
    rp, bp, left, right = _ghidra_fallback_zero_fill_case(tmp_path)
    for document in (left, right):
        _use_angr_loader_backing(document)
        loader = document["extensions"]["angr"]["loader"]["sections"]
        for section, metadata in zip(document["sections"][1:], loader[1:]):
            section.update(address=0x8100, size=0,
                           sha256=hashlib.sha256(b"").hexdigest())
            metadata.update(address=0x8100, size=0)
    left["extensions"]["angr"]["loader"]["sections"][2]["initialized"] = True

    with pytest.raises(ComparisonError, match="conflicting section backing metadata"):
        compare_artifacts(rp, bp, left, right, "exact-sections")


def test_overlapping_file_backed_sections_and_artifact_alias_are_rejected(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    duplicate = deepcopy(left["sections"][0]); duplicate["name"] = ".other"; duplicate["address"] += 0x100
    left["sections"].append(duplicate)
    with pytest.raises(ComparisonError, match="overlap"):
        compare_artifacts(rp, bp, left, right, "exact-image")
    with pytest.raises(ComparisonError, match="alias"):
        compare_artifacts(rp, rp, analysis(), analysis(), "exact-image")


def _discontiguous_function_envelope_case(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    for document in (left, right):
        original = document["functions"][0]
        middle = deepcopy(original["instructions"][1])
        original["blocks"] = [
            {"address": 0x1000, "size": 5, "successors": []},
            {"address": 0x100A, "size": 2, "successors": []},
        ]
        original["instructions"] = [original["instructions"][0], original["instructions"][2]]
        inner = {
            "address": 0x1005, "size": 5, "names": ["gap_fragment"],
            "blocks": [{"address": 0x1005, "size": 5, "successors": []}],
            "instructions": [middle], "calls": [], "confidence": 1.0,
        }
        document["functions"].append(inner)
    return rp, bp, left, right


def test_disjoint_occupied_intervals_do_not_make_overlapping_function_envelopes(tmp_path):
    rp, bp, left, right = _discontiguous_function_envelope_case(tmp_path)

    report = compare_artifacts(rp, bp, left, right, "normalized-functions")

    assert report["acceptance"]["normalized-functions"] is True
    assert not any(item["reason"] == "overlapping functions"
                   for item in report["categories"]["layout"])


@pytest.mark.parametrize("shared", ["instruction", "block"])
def test_shared_instruction_or_block_bytes_are_true_function_overlaps(tmp_path, shared):
    rp, bp, left, right = _discontiguous_function_envelope_case(tmp_path)
    for document in (left, right):
        outer, inner = document["functions"]
        if shared == "instruction":
            outer["blocks"].append({"address": 0x1005, "size": 5, "successors": []})
            outer["instructions"].append(deepcopy(inner["instructions"][0]))
        else:
            outer["blocks"].append({"address": 0x1007, "size": 1, "successors": []})
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")

    assert not report["acceptance"]["normalized-functions"]
    assert all(item["status"] == "different" for item in report["functions"])
    assert any(item["reason"] == "overlapping functions" for item in report["categories"]["layout"])


def test_missing_function_occupancy_evidence_remains_conservative(tmp_path):
    rp, bp, left, right = _discontiguous_function_envelope_case(tmp_path)
    for document in (left, right):
        document["functions"][1]["blocks"] = []
        document["functions"][1]["instructions"] = []

    report = compare_artifacts(rp, bp, left, right, "normalized-functions")

    assert not report["acceptance"]["normalized-functions"]
    assert any(item["reason"] == "overlapping functions"
               for item in report["categories"]["layout"])


@pytest.mark.parametrize("mutation", ["order", "section"])
def test_function_occupancy_evidence_fails_closed_when_noncanonical(tmp_path, mutation):
    import binrecon.compare as module
    from binrecon.normalize import normalize_analysis

    _, _, document, _ = _discontiguous_function_envelope_case(tmp_path)
    function = normalize_analysis(document)["functions"][0]
    if mutation == "order":
        function["blocks"].reverse()
        message = "noncanonical"
    else:
        function["blocks"][0]["section"] = deepcopy(function["blocks"][0]["section"])
        function["blocks"][0]["section"]["name"] = ".other"
        message = "owning section"

    with pytest.raises(ComparisonError, match=message):
        module._occupied_intervals(function)


def test_large_sparse_images_are_compared_in_chunks(tmp_path):
    size = 2 * 1024 * 1024 + 17
    data = b"\0" * size
    rp, bp, left, right = _case(tmp_path, data, data)
    for document in (left, right):
        document["functions"] = []; document["symbols"] = []; document["relocations"] = []
        document["references"] = []; document["extensions"] = {}
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    assert report["acceptance"]["exact-image"] is True


def test_mutation_during_chunked_snapshot_is_rejected(tmp_path, monkeypatch):
    import binrecon.compare as module
    data = b"A" * (module.CHUNK_SIZE + 8)
    rp, bp, left, right = _case(tmp_path, data, data)
    real_read = module.os.read; changed = False
    def mutating_read(descriptor, size):
        nonlocal changed
        value = real_read(descriptor, size)
        if value and not changed:
            changed = True
            with rp.open("r+b") as stream:
                stream.seek(-1, 2); stream.write(b"B"); stream.flush()
        return value
    monkeypatch.setattr(module.os, "read", mutating_read)
    with pytest.raises(ComparisonError, match="changed"):
        compare_artifacts(rp, bp, left, right, "exact-image")


@pytest.mark.parametrize(("offset", "replacement"), [
    (5, b"\x66"),       # operand-size prefix/access width
    (6, b"\x79"),       # literal constant
    (10, b"\xe5"),      # port instruction opcode
    (11, b"\x81"),      # port constant
])
def test_actual_instruction_bytes_override_stale_analyzer_bytes(tmp_path, offset, replacement):
    original = b"\xe8\x78\x56\x34\x12\x3d\x78\x56\x34\x12\xe4\x80" + b"\0" * 52
    changed = bytearray(original); changed[offset:offset + 1] = replacement
    rp, bp, left, right = _case(tmp_path, original, bytes(changed))
    right["sections"][0]["sha256"] = hashlib.sha256(changed).hexdigest()
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["acceptance"]["normalized-functions"] is False
    assert any(item["kind"] == "analyzer-inconsistency"
               for item in report["categories"]["code"])


def test_section_virtual_address_is_exact_layout_but_functions_are_rebase_tolerant(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    delta = 0x1000
    right["sections"][0]["address"] += delta
    for symbol in right["symbols"]: symbol["address"] += delta
    for relocation in right["relocations"]: relocation["address"] += delta
    right["extensions"]["macho"]["relocations"][0]["address"] += delta
    for reference in right["references"]:
        reference["address"] += delta
        if reference["target"] is not None: reference["target"] += delta
    for function in right["functions"]:
        function["address"] += delta
        for block in function["blocks"]:
            block["address"] += delta
            for successor in block["successors"]: successor["target"] += delta
        for instruction in function["instructions"]: instruction["address"] += delta
        for call in function["calls"]:
            call["address"] += delta
            if call["target"] is not None: call["target"] += delta
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["acceptance"]["normalized-functions"] is True
    assert report["acceptance"]["exact-sections"] is False
    assert report["sections"][0]["reference"]["address"] != report["sections"][0]["rebuilt"]["address"]


def test_true_two_section_reordering_fails_exact_sections(tmp_path):
    data = b"TEXTDATA"
    rp, bp, left, right = _case(tmp_path, data, data)
    sections = [
        {"name": ".text", "address": 0x1000, "offset": 0, "size": 4,
         "permissions": "rx", "sha256": hashlib.sha256(b"TEXT").hexdigest()},
        {"name": ".data", "address": 0x2000, "offset": 4, "size": 4,
         "permissions": "rw", "sha256": hashlib.sha256(b"DATA").hexdigest()},
    ]
    for document in (left, right):
        document["sections"] = deepcopy(sections); document["functions"] = []
        document["symbols"] = []; document["relocations"] = []; document["references"] = []
        document["extensions"] = {}
    right["sections"].reverse()
    report = compare_artifacts(rp, bp, left, right, "exact-sections")
    assert report["acceptance"]["exact-sections"] is False
    assert report["categories"]["layout"]


def test_top_level_strings_imports_and_relocations_are_compared(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    strings = [{"address": 0x1030, "value": "a", "encoding": "ascii"},
               {"address": 0x1032, "value": "b", "encoding": "ascii"}]
    left["strings"] = deepcopy(strings); right["strings"] = list(reversed(deepcopy(strings)))
    left["imports"] = [{"name": "imp", "address": None}]
    right["imports"] = [{"name": "other", "address": None}]
    right["relocations"][0]["addend"] = -8
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert any(item["path"] == "/strings" for item in report["categories"]["symbol-string-order"])
    assert any(item["path"] == "/imports" for item in report["categories"]["metadata"])
    assert any(item.get("path") == "/relocations" for item in report["categories"]["relocation"])


def test_exact_json_pointer_ignore_and_invalid_paths(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    left["extensions"]["header"] = {"timestamp": 1, "flags": 7}
    right["extensions"]["header"] = {"timestamp": 2, "flags": 7}
    report = compare_artifacts(rp, bp, left, right, "exact-image",
                               ignore_metadata=["/extensions/header/timestamp"])
    assert not report["categories"]["metadata"]
    for ignored in (["extensions.header.timestamp"], ["/extensions"],
                    ["/extensions/header/missing"],
                    ["/extensions/header/timestamp", "/extensions/header/timestamp"]):
        with pytest.raises(ComparisonError, match="ignore"):
            compare_artifacts(rp, bp, left, right, "exact-image", ignored)


def test_validator_rejects_unknown_evidence_kind_and_forged_acceptance(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    right["functions"][0]["blocks"][0]["successors"] = []
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    report["categories"]["code"][0]["kind"] = "made-up"
    with pytest.raises(ComparisonError): validate_comparison_report(report)
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    report["acceptance"]["normalized-functions"] = True
    report["selected"]["passed"] = True
    with pytest.raises(ComparisonError): validate_comparison_report(report)


def test_mutation_during_later_section_reads_is_rejected(tmp_path, monkeypatch):
    import binrecon.compare as module
    rp, bp, left, right = _case(tmp_path)
    original = module._Artifact.read_at; calls = 0
    def mutate_during_sections(self, offset, size):
        nonlocal calls
        calls += 1; value = original(self, offset, size)
        if calls == 3:
            with bp.open("r+b") as stream:
                stream.seek(-1, 2); stream.write(b"X"); stream.flush()
        return value
    monkeypatch.setattr(module._Artifact, "read_at", mutate_during_sections)
    with pytest.raises(ComparisonError, match="changed"):
        compare_artifacts(rp, bp, left, right, "exact-image")


def test_function_crossing_section_boundary_is_rejected(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    data = rp.read_bytes()
    for document in (left, right):
        document["sections"] = [
            {"name": ".text", "address": 0x1000, "offset": 0, "size": 4,
             "permissions": "rx", "sha256": hashlib.sha256(data[:4]).hexdigest()},
            {"name": ".tail", "address": 0x1004, "offset": 4, "size": len(data) - 4,
             "permissions": "rx", "sha256": hashlib.sha256(data[4:]).hexdigest()}]
    with pytest.raises(ComparisonError, match="one section"):
        compare_artifacts(rp, bp, left, right, "normalized-functions")


def test_evidence_validator_rejects_bool_ranges_bad_hash_bytes_path_and_counts(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    changed = bytearray(bp.read_bytes()); changed[6] ^= 1; bp.write_bytes(changed)
    right["input"]["sha256"] = hashlib.sha256(changed).hexdigest()
    right["sections"][0]["sha256"] = hashlib.sha256(changed).hexdigest()
    probes = []
    base = compare_artifacts(rp, bp, left, right, "normalized-functions")
    item = next(value for value in base["categories"]["code"] if "start" in value)
    probes.append(lambda report: report["categories"]["code"][report["categories"]["code"].index(
        next(value for value in report["categories"]["code"] if "start" in value))].update(start=True))
    probes.append(lambda report: report["reference"].update(sha256="a" * 64))
    probes.append(lambda report: next(value for value in report["categories"]["code"]
                                      if "start" in value).update(reference="A"))
    probes.append(lambda report: report["category_counts"].update(code=True))
    for probe in probes:
        report = deepcopy(base); probe(report)
        with pytest.raises(ComparisonError): validate_comparison_report(report)
    layout = deepcopy(base["categories"]["metadata"][0])
    layout["path"] = "/bad~2"
    layout_report = deepcopy(base); layout_report["categories"]["metadata"][0] = layout
    layout_report["categories"]["metadata"].sort(key=lambda value: json.dumps(value, sort_keys=True))
    with pytest.raises(ComparisonError): validate_comparison_report(layout_report)


def _same_name_case(tmp_path):
    data = b"\x90" + b"A" * 31 + b"\xC3" + b"B" * 31
    rp, bp, left, right = _case(tmp_path, data, data)
    sections = [
        {"name": ".text", "address": 0x1000, "offset": 0, "size": 32,
         "permissions": "rx", "sha256": hashlib.sha256(data[:32]).hexdigest()},
        {"name": ".text", "address": 0x2000, "offset": 32, "size": 32,
         "permissions": "rx", "sha256": hashlib.sha256(data[32:]).hexdigest()}]
    functions = []
    for address, byte, name in ((0x1000, "90", "first"), (0x2000, "C3", "second")):
        functions.append({"address": address, "size": 1, "names": [name],
            "blocks": [{"address": address, "size": 1, "successors": []}],
            "instructions": [{"address": address, "bytes": byte, "mnemonic": "nop",
                "operands": "", "normalized_operands": "", "relocations": []}],
            "calls": [], "confidence": 1.0})
    for document in (left, right):
        document["sections"] = deepcopy(sections); document["functions"] = deepcopy(functions)
        document["symbols"] = []; document["relocations"] = []; document["references"] = []
        document["extensions"] = {}
    return rp, bp, left, right


def test_same_name_sections_have_collision_free_function_keys(tmp_path):
    rp, bp, left, right = _same_name_case(tmp_path)
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["acceptance"]["normalized-functions"] is True
    assert len(report["functions"]) == 2
    assert [item["key"]["name_occurrence"] for item in report["functions"]] == [0, 1]
    assert [item["reference"]["name_occurrence"] for item in report["sections"]] == [0, 1]


def test_same_name_section_content_change_rebase_and_reorder_do_not_collapse(tmp_path):
    rp, bp, left, right = _same_name_case(tmp_path)
    changed = bytearray(bp.read_bytes()); changed[32] = 0x90; bp.write_bytes(changed)
    right["input"]["sha256"] = hashlib.sha256(changed).hexdigest()
    right["sections"][1]["sha256"] = hashlib.sha256(changed[32:]).hexdigest()
    right["functions"][1]["instructions"][0]["bytes"] = "90"
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert len(report["functions"]) == 2
    assert [item["status"] for item in report["functions"]] == ["assembly-matched", "different"]
    delta = 0x1000
    bp.write_bytes(rp.read_bytes())
    right = deepcopy(left)
    for section in right["sections"]: section["address"] += delta
    for function in right["functions"]:
        function["address"] += delta
        function["blocks"][0]["address"] += delta
        function["instructions"][0]["address"] += delta
    report = compare_artifacts(rp, rp.with_name("rebuilt.bin"), left, right, "normalized-functions")
    assert report["acceptance"]["normalized-functions"] is True
    assert report["acceptance"]["exact-sections"] is False
    right["sections"].reverse()
    report = compare_artifacts(rp, rp.with_name("rebuilt.bin"), left, right, "exact-sections")
    assert len(report["functions"]) == 2
    assert report["acceptance"]["exact-sections"] is False


def test_same_name_section_hash_change_outside_functions_retains_both_matches(tmp_path):
    rp, bp, left, right = _same_name_case(tmp_path)
    changed = bytearray(bp.read_bytes()); changed[40] ^= 1; bp.write_bytes(changed)
    right["input"]["sha256"] = hashlib.sha256(changed).hexdigest()
    right["sections"][1]["sha256"] = hashlib.sha256(changed[32:]).hexdigest()
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert len(report["functions"]) == 2
    assert all(item["status"] == "assembly-matched" for item in report["functions"])
    assert report["acceptance"]["normalized-functions"] is True
    assert report["acceptance"]["exact-sections"] is False


def test_ambiguous_same_name_structural_order_is_rejected(tmp_path):
    rp, bp, left, right = _same_name_case(tmp_path)
    for document in (left, right):
        document["functions"] = []
        document["sections"][0]["size"] = document["sections"][1]["size"] = 0
        empty_hash = hashlib.sha256(b"").hexdigest()
        document["sections"][0]["sha256"] = document["sections"][1]["sha256"] = empty_hash
        document["sections"][1]["offset"] = document["sections"][0]["offset"]
        document["sections"][1]["address"] = document["sections"][0]["address"]
    with pytest.raises(ComparisonError, match="ambiguous"):
        compare_artifacts(rp, bp, left, right, "normalized-functions")


@pytest.mark.parametrize(("sections", "start", "end", "expected"), [
    ([{"offset": 0, "size": 4}], 3, 6,
     [("metadata", "bytes within section ranges differ", 3, 4),
      ("padding", "bytes outside sections differ", 4, 6)]),
    ([{"offset": 4, "size": 4}], 2, 6,
     [("metadata", "header or load-command bytes differ", 2, 4),
      ("metadata", "bytes within section ranges differ", 4, 6)]),
    ([{"offset": 0, "size": 2}, {"offset": 4, "size": 2}], 3, 5,
     [("padding", "bytes outside sections differ", 3, 4),
      ("metadata", "bytes within section ranges differ", 4, 5)]),
])
def test_diff_ranges_split_at_section_and_padding_boundaries(tmp_path, sections, start, end, expected):
    data = bytearray(b"ABCDEFGH"); changed = bytearray(data); changed[start:end] = b"X" * (end - start)
    rp, bp, left, right = _case(tmp_path, bytes(data), bytes(changed))
    for document, raw in ((left, data), (right, changed)):
        document["sections"] = []
        for index, spec in enumerate(sections):
            offset, size = spec["offset"], spec["size"]
            document["sections"].append({"name": f".s{index}", "address": 0x1000 + offset,
                "offset": offset, "size": size, "permissions": "r",
                "sha256": hashlib.sha256(raw[offset:offset + size]).hexdigest()})
        document["functions"] = []; document["symbols"] = []; document["relocations"] = []
        document["references"] = []; document["extensions"] = {}
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    ranges = [(category, item["reason"], item["start"], item["end"])
              for category in ("metadata", "padding") for item in report["categories"][category]
              if item["kind"] in ("byte-range", "section-byte-range")]
    assert sorted(ranges) == sorted(expected)


def test_collection_order_categories_are_distinct(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    for document in (left, right):
        document["functions"] = []; document["extensions"] = {}; document["references"] = []
        document["symbols"] = [
            {"name": "a", "address": 0x1010, "binding": "local", "section": ".text"},
            {"name": "b", "address": 0x1014, "binding": "local", "section": ".text"}]
        document["strings"] = [
            {"address": 0x1020, "value": "a", "encoding": "ascii"},
            {"address": 0x1022, "value": "b", "encoding": "ascii"}]
        document["imports"] = [{"name": "a", "address": None}, {"name": "b", "address": None}]
        document["relocations"] = [
            {"address": 0x1030, "kind": "absolute-32", "target": "a", "addend": 0},
            {"address": 0x1034, "kind": "absolute-32", "target": "b", "addend": 0}]
    for name in ("symbols", "strings", "imports", "relocations"): right[name].reverse()
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    order_paths = {item["path"] for item in report["categories"]["symbol-string-order"]}
    assert order_paths == {"/symbols", "/strings"}
    assert any(item["path"] == "/imports" and item["reason"] == "imports reordered"
               for item in report["categories"]["metadata"])
    assert any(item["path"] == "/relocations" and item["reason"] == "relocations reordered"
               for item in report["categories"]["relocation"])
    assert report["acceptance"]["normalized-functions"] is False


def test_diff_spanning_differently_placed_sections_splits_at_both_layouts(tmp_path):
    reference = b"ABCDEFGH"; rebuilt = b"ABXXXXGH"
    rp, bp, left, right = _case(tmp_path, reference, rebuilt)
    left_section = {"name": ".data", "address": 0x1000, "offset": 2, "size": 2,
                    "permissions": "r", "sha256": hashlib.sha256(reference[2:4]).hexdigest()}
    right_section = {"name": ".data", "address": 0x1000, "offset": 4, "size": 2,
                     "permissions": "r", "sha256": hashlib.sha256(rebuilt[4:6]).hexdigest()}
    for document, section in ((left, left_section), (right, right_section)):
        document["sections"] = [section]; document["functions"] = []
        document["symbols"] = []; document["relocations"] = []; document["references"] = []
        document["extensions"] = {}
    report = compare_artifacts(rp, bp, left, right, "exact-sections")
    pieces = [(item["start"], item["end"]) for item in report["categories"]["metadata"]
              if item["kind"] == "section-byte-range" and
              item["reason"] == "bytes within section ranges differ"]
    assert pieces == [(2, 4), (4, 6)]
    assert report["acceptance"]["exact-sections"] is False


def test_unlisted_function_gap_bytes_are_artifact_authoritative(tmp_path):
    original = b"\xe8\x78\x56\x34\x12\x3d\x78\x56\x34\x12\xe4\x80" + b"\0" * 52
    changed = bytearray(original); changed[6] ^= 1
    rp, bp, left, right = _case(tmp_path, original, bytes(changed))
    for document in (left, right):
        document["functions"][0]["instructions"] = document["functions"][0]["instructions"][:1]
    right["sections"][0]["sha256"] = hashlib.sha256(changed).hexdigest()
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["functions"][0]["masked_equal"] is False
    assert report["acceptance"]["normalized-functions"] is False
    assert any(item["reason"] == "function range bytes differ" for item in report["categories"]["code"])


def test_equal_unlisted_gaps_and_large_function_stream_compare(tmp_path):
    size = 2 * 1024 * 1024 + 7; data = b"\x90" + b"G" * (size - 1)
    rp, bp, left, right = _case(tmp_path, data, data)
    for document in (left, right):
        document["sections"][0].update(size=size, sha256=hashlib.sha256(data).hexdigest())
        function = document["functions"][0]; function["size"] = size
        function["blocks"] = [{"address": 0x1000, "size": size, "successors": []}]
        function["instructions"] = [{"address": 0x1000, "bytes": "90", "mnemonic": "nop",
            "operands": "", "normalized_operands": "", "relocations": []}]
        function["calls"] = []; document["relocations"] = []; document["references"] = []
        document["extensions"] = {}
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["functions"][0]["masked_equal"] is True
    assert report["acceptance"]["normalized-functions"] is True


def test_normalized_operand_change_fails_but_direct_call_rename_does_not(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    right["functions"][0]["instructions"][1]["operands"] = " EAX , 0x12345678 "
    right["functions"][0]["calls"][0]["name"] = "renamed_display_alias"
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["acceptance"]["normalized-functions"] is True
    right["functions"][0]["instructions"][1]["normalized_operands"] = "eax, 0xDEADBEEF"
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["acceptance"]["normalized-functions"] is False
    assert "instruction semantics differ" in report["functions"][0]["reasons"]


def test_direct_call_target_change_and_unresolved_name_change_fail(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    right["functions"][0]["calls"][0]["target"] = 0x1030
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["acceptance"]["normalized-functions"] is False
    right = deepcopy(left)
    for document, name in ((left, "external_a"), (right, "external_b")):
        document["functions"][0]["calls"] = [{"address": 0x1000, "target": None, "name": name}]
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["acceptance"]["normalized-functions"] is False


def test_function_records_use_natural_numeric_order(tmp_path):
    data = bytes(range(32))
    rp, bp, left, right = _case(tmp_path, data, data)
    functions = []
    for offset in range(12):
        functions.append({"address": 0x1000 + offset, "size": 1, "names": [f"f{offset}"],
            "blocks": [{"address": 0x1000 + offset, "size": 1, "successors": []}],
            "instructions": [{"address": 0x1000 + offset, "bytes": f"{data[offset]:02X}",
                "mnemonic": "db", "operands": "", "normalized_operands": "", "relocations": []}],
            "calls": [], "confidence": 1.0})
    for document in (left, right):
        document["functions"] = deepcopy(functions); document["relocations"] = []
        document["references"] = []; document["symbols"] = []; document["extensions"] = {}
    right["functions"].reverse()
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert [item["key"]["start"] for item in report["functions"]] == list(range(12))
    assert report["acceptance"]["normalized-functions"] is True
    validate_comparison_report(report)


def test_evidence_cap_keeps_full_missing_function_totals(tmp_path):
    count = 300; data = b"\x90" * count
    rp, bp, left, right = _case(tmp_path, data, data)
    functions = [{"address": 0x1000 + index, "size": 1, "names": [f"f{index}"],
        "blocks": [{"address": 0x1000 + index, "size": 1, "successors": []}],
        "instructions": [{"address": 0x1000 + index, "bytes": "90", "mnemonic": "nop",
            "operands": "", "normalized_operands": "", "relocations": []}],
        "calls": [], "confidence": 1.0} for index in range(count)]
    for document in (left, right):
        document["sections"][0].update(size=count, sha256=hashlib.sha256(data).hexdigest())
        document["functions"] = deepcopy(functions); document["relocations"] = []
        document["references"] = []; document["symbols"] = []; document["extensions"] = {}
    right["functions"] = []
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert len(report["functions"]) == count
    assert report["category_counts"]["code"] == count
    assert report["category_omitted"]["code"] == count - len(report["categories"]["code"])
    validate_comparison_report(report)


def test_no_section_and_zero_fill_only_differences_are_header_metadata(tmp_path):
    rp, bp, left, right = _case(tmp_path, b"A", b"B")
    for document in (left, right):
        document["sections"] = []; document["functions"] = []; document["symbols"] = []
        document["relocations"] = []; document["references"] = []; document["extensions"] = {}
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    assert any(item["reason"] == "header or load-command bytes differ"
               for item in report["categories"]["metadata"])
    zero_hash = hashlib.sha256(b"\0" * 16).hexdigest()
    for document in (left, right):
        document["sections"] = [{"name": ".bss", "address": 0x2000, "offset": 99,
            "size": 16, "permissions": "rw", "sha256": zero_hash}]
        document["extensions"] = {"macho": {"sections": [{"name": ".bss", "address": 0x2000,
            "offset": 99, "size": 16, "zero_fill": True}]}}
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    assert any(item["reason"] == "header or load-command bytes differ"
               for item in report["categories"]["metadata"])


def test_relocation_in_unlisted_gap_is_not_masked(tmp_path):
    original = b"\xAA\x11\x22\x33\x44\x90" + b"G" * 58
    changed = bytearray(original); changed[1:5] = b"\x55\x66\x77\x88"
    rp, bp, left, right = _case(tmp_path, original, bytes(changed))
    for document, raw in ((left, original), (right, changed)):
        document["sections"][0]["sha256"] = hashlib.sha256(raw).hexdigest()
        function = document["functions"][0]
        function["instructions"] = [{"address": 0x1005, "bytes": "90", "mnemonic": "nop",
            "operands": "", "normalized_operands": "", "relocations": []}]
        function["calls"] = []; document["references"] = []
        document["relocations"][0]["address"] = 0x1001
        document["extensions"]["macho"]["relocations"][0]["address"] = 0x1001
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["functions"][0]["masked_equal"] is False
    assert report["acceptance"]["normalized-functions"] is False


def test_overlapping_and_out_of_range_instruction_intervals_reject(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    overlap = deepcopy(left); overlap["functions"][0]["instructions"][1]["address"] = 0x1004
    with pytest.raises(ComparisonError): compare_artifacts(rp, bp, overlap, right, "normalized-functions")
    outside = deepcopy(left); outside["functions"][0]["instructions"][-1]["address"] = 0x100C
    with pytest.raises(ComparisonError): compare_artifacts(rp, bp, outside, right, "normalized-functions")


def test_interval_classification_scales_to_maximum_sections(tmp_path):
    rp, bp, left, right = _case(tmp_path, b"A", b"B")
    empty_hash = hashlib.sha256(b"").hexdigest()
    sections = [{"name": f".z{index}", "address": 0x1000 + index, "offset": 0,
                 "size": 0, "permissions": "r", "sha256": empty_hash}
                for index in range(4096)]
    for document in (left, right):
        document["sections"] = deepcopy(sections); document["functions"] = []
        document["symbols"] = []; document["relocations"] = []; document["references"] = []
        document["extensions"] = {}
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    assert any(item["reason"] == "header or load-command bytes differ"
               for item in report["categories"]["metadata"])


@pytest.mark.parametrize("mutation", [
    lambda report: report.update(category_counts=[]),
    lambda report: report["category_omitted"].update(code=True),
    lambda report: report["functions"][0].update(reasons=[[]]),
    lambda report: report["functions"][0].update(masked_equal=1),
    lambda report: report["functions"][0].update(reference_sha256=[]),
    lambda report: report["sections"][0].update(layout_equal=1),
])
def test_malformed_report_mutations_raise_only_comparison_error(tmp_path, mutation):
    rp, bp, left, right = _case(tmp_path)
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    mutation(report)
    with pytest.raises(ComparisonError): validate_comparison_report(report)


def test_all_six_hundred_artifact_diff_runs_are_counted_beyond_sample_cap(tmp_path):
    reference = b"\0" * 1200
    rebuilt = bytearray(reference)
    for index in range(0, 1200, 2): rebuilt[index] = 1
    rp, bp, left, right = _case(tmp_path, reference, bytes(rebuilt))
    for document in (left, right):
        document["sections"] = []; document["functions"] = []; document["symbols"] = []
        document["relocations"] = []; document["references"] = []; document["extensions"] = {}
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    assert report["reason_totals"]["metadata"]["header or load-command bytes differ"] == 600
    assert report["category_counts"]["metadata"] == 600
    assert len(report["categories"]["metadata"]) == 256
    assert report["category_omitted"]["metadata"] == 344


def test_opcode_difference_with_relocation_does_not_claim_relocation_bytes(tmp_path):
    original = b"\xe8\x78\x56\x34\x12\x3d\x78\x56\x34\x12\xe4\x80" + b"\0" * 52
    changed = bytearray(original); changed[0] = 0xE9
    rp, bp, left, right = _case(tmp_path, original, bytes(changed))
    right["input"]["sha256"] = hashlib.sha256(changed).hexdigest()
    right["sections"][0]["sha256"] = hashlib.sha256(changed).hexdigest()
    right["functions"][0]["instructions"][0]["bytes"] = "E978563412"
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["acceptance"]["normalized-functions"] is False
    assert not any(item["reason"] == "relocation field bytes differ"
                   for item in report["categories"]["relocation"])


def test_relocation_evidence_requires_the_whole_masked_function_to_match(tmp_path):
    original = b"\xe8\x78\x56\x34\x12\x3d\x78\x56\x34\x12\xe4\x80" + b"\0" * 52
    changed = bytearray(original)
    changed[1:5] = b"\x11\x22\x33\x44"
    changed[5] = 0x3C
    rp, bp, left, right = _case(tmp_path, original, bytes(changed))
    right["functions"][0]["instructions"][0]["bytes"] = "E811223344"
    right["functions"][0]["instructions"][1]["bytes"] = "3C78563412"
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["functions"][0]["masked_equal"] is False
    assert not any(item["reason"] == "relocation field bytes differ"
                   for item in report["categories"]["relocation"])


def test_validator_rejects_evidence_record_summary_and_section_forgeries(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    key = report["functions"][0]["key"]
    forged = {"kind": "function-structure", "category": "code", "scope": "function",
              "reason": "cfg differs", "function": deepcopy(key),
              "reference": "different", "rebuilt": "different"}
    report["categories"]["code"] = [forged]
    report["category_counts"]["code"] = 1
    report["reason_totals"]["code"] = {"cfg differs": 1}
    with pytest.raises(ComparisonError): validate_comparison_report(report)
    left["functions"] = []; right["functions"] = []
    right["relocations"][0]["addend"] = -8
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    report["relocation_summary"].update(standalone_different_count=0,
                                        rejecting_count=0, compatible=True)
    report["acceptance"]["normalized-functions"] = True
    report["selected"]["passed"] = True
    with pytest.raises(ComparisonError): validate_comparison_report(report)

    left["relocations"] = []; right["relocations"] = []
    right["sections"][0]["address"] += 0x1000
    report = compare_artifacts(rp, bp, left, right, "exact-sections")
    report["sections"][0].update(layout_equal=True, status="matched", reasons=[])
    report["acceptance"]["exact-sections"] = True
    report["selected"]["passed"] = True
    with pytest.raises(ComparisonError): validate_comparison_report(report)


def test_validator_recomputes_function_booleans_from_reasons(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    right["functions"][0]["blocks"][0]["successors"] = []
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert "cfg differs" in report["functions"][0]["reasons"]
    report["functions"][0]["cfg_equal"] = True
    with pytest.raises(ComparisonError):
        validate_comparison_report(report)


def _inject_omitted_reason(report, category, reason):
    report["category_counts"][category] = 1
    report["category_omitted"][category] = 1
    report["reason_totals"][category] = {reason: 1}
    report["nonrecord_reason_totals"][category] = {reason: 1}


@pytest.mark.parametrize(("category", "reason"), [
    ("code", "analyzer bytes disagree with artifact"),
    ("code", "instruction semantics differ"),
    ("code", "instruction shape differs"),
    ("code", "instruction layout differs"),
    ("code", "instruction references differ"),
    ("code", "cfg differs"),
    ("code", "calls differ"),
    ("code", "missing reference function"),
    ("code", "missing rebuilt function"),
    ("code", "overlapping functions"),
    ("code", "function range bytes differ"),
    ("layout", "overlapping functions"),
    ("relocation", "relocation target semantics differ"),
    ("relocation", "relocation field bytes differ"),
    ("layout", "section layout differs"),
    ("metadata", "section content differs"),
    ("metadata", "analyzer section hash disagrees with artifact"),
])
def test_record_only_reasons_cannot_be_forged_as_omitted_nonrecord(
        tmp_path, category, reason):
    rp, bp, left, right = _case(tmp_path)
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    _inject_omitted_reason(report, category, reason)
    with pytest.raises(ComparisonError):
        validate_comparison_report(report)


@pytest.mark.parametrize(("category", "reason"), [
    ("padding", "metadata differs"),
    ("metadata", "bytes outside sections differ"),
    ("code", "relocations differ"),
    ("padding", "bytes within section ranges differ"),
])
def test_nonrecord_reason_category_swaps_are_rejected(tmp_path, category, reason):
    rp, bp, left, right = _case(tmp_path)
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    _inject_omitted_reason(report, category, reason)
    with pytest.raises(ComparisonError):
        validate_comparison_report(report)


def test_unknown_omitted_nonrecord_reason_is_rejected(tmp_path):
    rp, bp, left, right = _case(tmp_path)
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    _inject_omitted_reason(report, "metadata", "invented reason")
    with pytest.raises(ComparisonError):
        validate_comparison_report(report)


def test_legitimate_header_and_padding_nonrecord_reasons_validate(tmp_path):
    reference = b"ABCDEFGH"
    rebuilt = b"XBCDEFXH"
    rp, bp, left, right = _case(tmp_path, reference, rebuilt)
    for document, data in ((left, reference), (right, rebuilt)):
        document["sections"] = [{"name": ".text", "address": 0x1000, "offset": 2,
            "size": 4, "permissions": "r", "sha256": hashlib.sha256(data[2:6]).hexdigest()}]
        document["functions"] = []; document["symbols"] = []; document["relocations"] = []
        document["references"] = []; document["extensions"] = {}
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    assert report["nonrecord_reason_totals"]["metadata"] == {
        "header or load-command bytes differ": 1}
    assert report["nonrecord_reason_totals"]["padding"] == {
        "bytes outside sections differ": 1}
    validate_comparison_report(report)


@pytest.mark.parametrize(("change", "reason"), [
    ("different", "relocations differ"),
    ("reordered", "relocations reordered"),
])
def test_legitimate_standalone_relocation_nonrecord_reasons_validate(tmp_path, change, reason):
    rp, bp, left, right = _case(tmp_path)
    for document in (left, right):
        document["functions"] = []; document["extensions"] = {}
        document["relocations"].append({"address": 0x1008, "kind": "absolute-32",
                                        "target": "other", "addend": 0})
    if change == "different":
        right["relocations"][0]["addend"] = -8
    else:
        right["relocations"].reverse()
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    assert report["nonrecord_reason_totals"]["relocation"] == {reason: 1}
    assert report["relocation_summary"]["compatible"] is False
    assert report["acceptance"]["normalized-functions"] is False
    validate_comparison_report(report)


def _physical_section_case(tmp_path, reference, rebuilt, left_offset, right_offset):
    rp, bp, left, right = _case(tmp_path, reference, rebuilt)
    for document, data, offset in ((left, reference, left_offset),
                                   (right, rebuilt, right_offset)):
        document["sections"] = [{"name": ".data", "address": 0x1000, "offset": offset,
            "size": 2, "permissions": "r",
            "sha256": hashlib.sha256(data[offset:offset + 2]).hexdigest()}]
        document["functions"] = []; document["symbols"] = []; document["relocations"] = []
        document["references"] = []; document["extensions"] = {}
    return rp, bp, left, right


def test_moved_equal_section_bytes_are_physical_not_logical_content(tmp_path):
    rp, bp, left, right = _physical_section_case(
        tmp_path, b"XXABYY", b"ABXXYY", 2, 0)
    report = compare_artifacts(rp, bp, left, right, "exact-sections")
    assert report["sections"][0]["layout_equal"] is False
    assert report["sections"][0]["content_equal"] is True
    assert report["sections"][0]["reasons"] == ["section layout differs"]
    physical = [item for item in report["categories"]["metadata"]
                if item["reason"] == "bytes within section ranges differ"]
    assert physical and all(item["kind"] == "section-byte-range" for item in physical)
    assert report["nonrecord_reason_totals"]["metadata"] == {
        "bytes within section ranges differ": len(physical)}
    assert "section content differs" not in report["reason_totals"]["metadata"]
    assert report["acceptance"]["normalized-functions"] is True
    assert report["acceptance"]["exact-sections"] is False


def test_physical_runs_and_logical_section_content_are_distinct(tmp_path):
    rp, bp, left, right = _physical_section_case(
        tmp_path, b"XXABYY", b"CDXXYY", 2, 0)
    report = compare_artifacts(rp, bp, left, right, "exact-sections")
    assert report["sections"][0]["reasons"] == [
        "section content differs", "section layout differs"]
    assert report["reason_totals"]["metadata"]["section content differs"] == 1
    assert report["nonrecord_reason_totals"]["metadata"][
        "bytes within section ranges differ"] >= 1
    assert any(item["kind"] == "section-content"
               for item in report["categories"]["metadata"])
    assert any(item["kind"] == "section-byte-range"
               for item in report["categories"]["metadata"])


def test_physical_runs_in_an_unmatched_section_are_nonrecord(tmp_path):
    rp, bp, left, right = _physical_section_case(
        tmp_path, b"XXABYY", b"XXXXYY", 2, 0)
    right["sections"] = []
    report = compare_artifacts(rp, bp, left, right, "exact-sections")
    assert report["sections"][0]["reasons"] == ["section layout differs"]
    assert "section content differs" not in report["reason_totals"]["metadata"]
    assert report["nonrecord_reason_totals"]["metadata"][
        "bytes within section ranges differ"] >= 1


_ARTIFACT_BYTE_CASES = [
    ("metadata", "header or load-command bytes differ"),
    ("metadata", "bytes within section ranges differ"),
    ("padding", "bytes outside sections differ"),
]


@pytest.mark.parametrize(("category", "reason"), _ARTIFACT_BYTE_CASES)
def test_equal_identities_reject_omitted_only_artifact_byte_totals(tmp_path, category, reason):
    rp, bp, left, right = _case(tmp_path)
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    _inject_omitted_reason(report, category, reason)
    with pytest.raises(ComparisonError):
        validate_comparison_report(report)


@pytest.mark.parametrize(("identity_change", "category", "reason"), [
    ("sha", "metadata", "header or load-command bytes differ"),
    ("size", "metadata", "bytes within section ranges differ"),
    ("both", "padding", "bytes outside sections differ"),
])
def test_different_identities_accept_matching_omitted_artifact_byte_totals(
        tmp_path, identity_change, category, reason):
    rp, bp, left, right = _case(tmp_path)
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    if identity_change in ("sha", "both"):
        report["rebuilt"]["sha256"] = "A" * 64
    if identity_change in ("size", "both"):
        report["rebuilt"]["size"] += 1
    _inject_omitted_reason(report, category, reason)
    report["acceptance"]["exact-image"] = False
    validate_comparison_report(report)


@pytest.mark.parametrize("identity_change", ["sha", "size", "both"])
def test_different_identities_reject_zero_artifact_byte_totals(tmp_path, identity_change):
    rp, bp, left, right = _case(tmp_path)
    report = compare_artifacts(rp, bp, left, right, "normalized-functions")
    if identity_change in ("sha", "both"):
        report["rebuilt"]["sha256"] = "A" * 64
    if identity_change in ("size", "both"):
        report["rebuilt"]["size"] += 1
    report["acceptance"]["exact-image"] = False
    with pytest.raises(ComparisonError):
        validate_comparison_report(report)


def _retained_header_byte_report(tmp_path):
    rp, bp, left, right = _case(tmp_path, b"AB", b"XB")
    for document in (left, right):
        document["sections"] = []; document["functions"] = []; document["symbols"] = []
        document["relocations"] = []; document["references"] = []; document["extensions"] = {}
    return compare_artifacts(rp, bp, left, right, "exact-image")


@pytest.mark.parametrize("mutation", [
    lambda item, report: item.update(start=-1),
    lambda item, report: item.update(start=item["end"] + 1),
    lambda item, report: item.update(end=max(report["reference"]["size"],
                                               report["rebuilt"]["size"]) + 1),
    lambda item, report: item.update(reference="A"),
    lambda item, report: item.update(reference="AA" * (item["end"] - item["start"] + 1)),
    lambda item, report: item.update(reference=item["rebuilt"]),
])
def test_artifact_byte_evidence_rejects_bad_ranges_and_samples(tmp_path, mutation):
    report = _retained_header_byte_report(tmp_path)
    item = report["categories"]["metadata"][0]
    mutation(item, report)
    with pytest.raises(ComparisonError):
        validate_comparison_report(report)


def test_real_tail_size_difference_uses_empty_missing_side_sample(tmp_path):
    rp, bp, left, right = _case(tmp_path, b"ABC", b"ABCX")
    for document in (left, right):
        document["sections"] = []; document["functions"] = []; document["symbols"] = []
        document["relocations"] = []; document["references"] = []; document["extensions"] = {}
    report = compare_artifacts(rp, bp, left, right, "exact-image")
    item = report["categories"]["metadata"][0]
    assert (item["start"], item["end"], item["reference"], item["rebuilt"]) == (3, 4, "", "58")
    validate_comparison_report(report)
    forged = deepcopy(report)
    forged["categories"]["metadata"][0]["reference"] = "00"
    with pytest.raises(ComparisonError):
        validate_comparison_report(forged)


@pytest.mark.parametrize(("variant", "category", "reason", "kind"), [
    ("header", "metadata", "header or load-command bytes differ", "byte-range"),
    ("section", "metadata", "bytes within section ranges differ", "section-byte-range"),
    ("padding", "padding", "bytes outside sections differ", "byte-range"),
])
def test_retained_artifact_byte_variants_bind_to_different_identities(
        tmp_path, variant, category, reason, kind):
    if variant == "header":
        report = _retained_header_byte_report(tmp_path)
    elif variant == "section":
        rp, bp, left, right = _physical_section_case(
            tmp_path, b"XXABYY", b"ABXXYY", 2, 0)
        report = compare_artifacts(rp, bp, left, right, "exact-image")
    else:
        rp, bp, left, right = _case(tmp_path, b"AB", b"AX")
        for document in (left, right):
            document["sections"] = [{"name": ".head", "address": 0x1000, "offset": 0,
                "size": 1, "permissions": "r", "sha256": hashlib.sha256(b"A").hexdigest()}]
            document["functions"] = []; document["symbols"] = []; document["relocations"] = []
            document["references"] = []; document["extensions"] = {}
        report = compare_artifacts(rp, bp, left, right, "exact-image")
    retained = [item for item in report["categories"][category]
                if item["reason"] == reason and item["kind"] == kind]
    assert retained
    assert report["reference"]["sha256"] != report["rebuilt"]["sha256"]
    validate_comparison_report(report)
