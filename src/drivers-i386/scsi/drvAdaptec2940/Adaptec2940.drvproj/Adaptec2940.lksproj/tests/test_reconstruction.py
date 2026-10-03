"""Evidence-backed checks for the Adaptec 2940 SCSI reconstruction."""

import argparse
import hashlib
import json
import os
from pathlib import Path

from binrecon.macho import read_macho
from binrecon.schema import load_json, load_source_map


REPO_ROOT = Path(__file__).resolve().parents[7]
DRIVER = REPO_ROOT / "src/drivers-i386/scsi/drvAdaptec2940"
RECON = DRIVER / "reconstruction"
REFERENCE = Path(os.environ.get(
    "BINRECON_REFERENCE",
    r"C:\Users\raynorpat\Downloads\test\Drivers\i386\Adaptec2940SCSI.config\Adaptec2940SCSI_reloc",
))
REFERENCE_SIZE = 87676
REFERENCE_SHA256 = "08E6C11EEC125847F485C86250C94C4AFCC025E59CF085B0C8039B94B2E79DF7"
TEXT_SIZE = 32568
GENERATED = {
    (0x7F20, "+[Adaptec2940SCSIKernelServerInstance kernelServerInstance]"),
    (0x7F2C, "+[Adaptec2940SCSIVersion driverKitVersionForAdaptec2940SCSI]"),
}
REQUIRED_CASES = {
    "scb-page-boundary", "completion-timeout-order", "completion-reset-order",
    "short-transfer", "autosense-completion", "free-scb-exhaustion",
    "abort-active", "sequencer-readback-failure", "eeprom-failure", "init-unwind",
    "queue-chain-insert-remove", "scb-layout", "negotiation-message",
    "pci-device-match", "sequencer-runtime-patch", "register-width-order",
}


def _analysis_path(path=None):
    value = path or os.environ.get("ADAPTEC_ANALYSIS")
    assert value, "set ADAPTEC_ANALYSIS or pass --analysis"
    result = Path(value)
    assert result.is_file(), f"IDA analysis not generated: {result}"
    return result


def audit_inventory(analysis_path=None, repo_root=REPO_ROOT):
    analysis_file = _analysis_path(analysis_path)
    analysis = load_json(analysis_file)
    assert analysis["schema_version"] == "analysis-v1"
    assert analysis["input"]["sha256"].upper() == REFERENCE_SHA256
    assert analysis["analyzer"]["name"] == "IDA"
    assert analysis["analyzer"]["version"] == "9.4"
    functions = analysis["functions"]
    assert len(functions) == 170
    addresses = [function["address"] for function in functions]
    assert len(addresses) == len(set(addresses))

    generated, controllers, buses, c_functions = set(), set(), set(), set()
    for function in functions:
        names = function["names"]
        assert names
        for name in names:
            pair = (function["address"], name)
            if name.startswith("+[Adaptec2940SCSIKernelServerInstance ") \
                    or name.startswith("+[Adaptec2940SCSIVersion "):
                generated.add(pair)
            elif name.startswith(("+[SCSIBus", "-[SCSIBus")):
                buses.add(pair)
            elif name.startswith(("+[Adaptec2940", "-[Adaptec2940")):
                controllers.add(pair)
            else:
                c_functions.add(pair)
    assert generated == GENERATED
    assert len(controllers) == 30
    assert len(buses) == 13
    assert len(c_functions) == 125

    source_map = load_source_map(
        RECON / "source-map.json",
        reference_analysis=analysis,
        repo_root=Path(repo_root),
    )
    buckets = ("mapped", "unmapped", "duplicate_candidates", "boundary_disputed")
    assert sum(len(source_map[key]) for key in buckets) == 170
    assert len({entry["address"] for key in buckets for entry in source_map[key]}) == 170

    ledger = json.loads((RECON / "ledger.json").read_text(encoding="utf-8"))
    assert ledger["schema_version"] == "ledger-v1"
    assert ledger["reference_sha256"].upper() == REFERENCE_SHA256
    assert len(ledger["entries"]) == 170
    assert {entry["address"] for entry in ledger["entries"]} == set(addresses)
    published = REPO_ROOT / "tools/binrecon/out/adaptec2940/baseline"
    for entry in ledger["entries"]:
        for artifact in entry["artifacts"]:
            artifact_path = published / artifact["path"]
            assert artifact_path.is_file(), f"missing ledger evidence: {artifact_path}"
            digest = hashlib.sha256(artifact_path.read_bytes()).hexdigest().upper()
            assert digest == artifact["sha256"], f"ledger artifact digest mismatch: {artifact_path}"

    cases = json.loads((RECON / "reference-cases.json").read_text(encoding="utf-8"))
    found_cases = {case["id"] for case in cases["cases"]}
    assert found_cases == REQUIRED_CASES
    for case in cases["cases"]:
        assert case["evidence"], f"case has no evidence: {case['id']}"
        assert all(item["address"] is not None for item in case["evidence"]), case["id"]
        assert case["expected"], case["id"]

    interfaces = (RECON / "interfaces.md").read_text(encoding="utf-8")
    for marker in ("Controller (30)", "Bus (13)", "C (125)", "Generated (2)",
                   "Adaptec2940` — 396 bytes", "SCSIBus` — 588 bytes",
                   "P_Seq_01", "P_SeqExist"):
        assert marker in interfaces, marker
    return True


def test_reference_identity():
    document = read_macho(REFERENCE)
    assert document["input"]["size"] == REFERENCE_SIZE
    assert document["input"]["sha256"] == REFERENCE_SHA256
    assert document["input"]["architecture"] == "i386"
    assert document["input"]["endianness"] == "little"
    text = next(section for section in document["sections"]
                if section["name"] == "__TEXT,__text")
    assert text["address"] == 0
    assert text["size"] == TEXT_SIZE


def test_inventory_partition():
    assert audit_inventory()


def _main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--audit", choices=("inventory",))
    parser.add_argument("--analysis")
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    args, pytest_args = parser.parse_known_args()
    if args.audit:
        audit_inventory(args.analysis, args.repo_root)
        print("inventory audit passed")
        return 0
    import pytest
    return pytest.main([str(Path(__file__)), *pytest_args])


if __name__ == "__main__":
    raise SystemExit(_main())
